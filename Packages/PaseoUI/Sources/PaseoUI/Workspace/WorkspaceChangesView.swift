#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The "Changes" page of the workspace panel: branch and ahead/behind, the PR badge, a
/// compare switch (Uncommitted / vs base), the changed-files list, and the commit/push bar.
/// The per-file unified diff opens in `WorkspaceChangesDiffView`.
struct WorkspaceChangesView: View {
    let session: HostSession
    let checkout: CheckoutStore
    /// The open chat's agent, the default recipient for review feedback.
    var agentId: String? = nil

    @State private var compare: ChangesCompare = .uncommitted
    @State private var openFile: ParsedDiffFile?
    @State private var openCommit: CheckoutCommit?
    @State private var showCommitSheet = false
    @State private var pendingDiscard: ParsedDiffFile?
    @State private var dismissedError: String?
    @State private var showCreatePRSheet = false
    @State private var createPRTitle = ""
    @State private var createPRBody = ""
    @State private var createPRFailure: String?
    @State private var mergeCandidate: PullRequestMergeMethod?
    @State private var showBaseBranchPicker = false
    @State private var showBranchSwitcher = false
    @AppStorage(PaseoSettingsKeys.diffHideWhitespace) private var hideWhitespace = false
    @AppStorage(PaseoSettingsKeys.diffWrapLongLines) private var wrapLongLines = false
    @AppStorage(PaseoSettingsKeys.diffCollapseAllHunks) private var collapseAllHunks = false
    /// The latest compare-switch reload. Each flip chains onto the previous one so quick
    /// Uncommitted/Base toggles finish in order rather than racing.
    @State private var diffReload: Task<Void, Never>?

    @Environment(\.toast) private var toast
    @Environment(\.openURL) private var openURL

    /// The modern-diff helper for this checkout. Idempotent: the same instance is returned while
    /// the workspace is open. Created through the store (never constructed by hand).
    private var extras: WorkspaceGitExtras {
        session.gitExtras.workspace(for: checkout)
    }

    /// T15's git actions for this checkout. Created through the store (never by hand).
    private var gitActions: WorkspaceGitActions {
        session.gitExtras.gitActions(for: checkout)
    }

    /// T17's PR timeline for this checkout. Created through the store (never by hand).
    private var timeline: PullRequestTimelineStore {
        session.gitExtras.timeline(for: checkout)
    }

    /// The ref the "vs base" comparison diffs against. Daemons with the modern pipeline prefer
    /// `comparisonBaseRef`; everyone else uses the exact, then the plain, base ref.
    private var baseRef: String? {
        let status = checkout.status
        let modern = extras.capabilities.supportsModernDiff
        let raw = (modern ? status?.comparisonBaseRef : nil) ?? status?.baseRefExact ?? status?.baseRef
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var branchLabel: String {
        currentBranch ?? "Detached HEAD"
    }

    /// The branch the workspace is on, or nil for a detached HEAD. Upstream's switcher has no
    /// trigger without a branch name (`branch-switcher.tsx`).
    private var currentBranch: String? {
        extras.currentBranch ?? checkout.branch
    }

    /// Git action failures (pull, update from base, merge, auto-merge) land on `gitActions`. A merge
    /// conflict has its own banner, and the Create PR sheet shows its own failure.
    private var visibleError: String? {
        let gitError =
            gitActions.lastFailure?.code == .mergeConflict || showCreatePRSheet
            ? nil : gitActions.actionError
        let error = gitError ?? extras.actionError ?? checkout.actionError
        guard let error, error != dismissedError else { return nil }
        return error
    }

    private var files: [ParsedDiffFile] { extras.files }

    var body: some View {
        // Until the first status lands we don't know whether this is a git repo; show the
        // scaffolding (it reads "Loading changes…") rather than flashing the not-git state.
        if !checkout.isGit && checkout.status != nil {
            notGitState
        } else {
            NavigationStack {
                root
                    .toolbarVisibility(.hidden, for: .navigationBar)
                    .navigationDestination(item: $openFile) { file in
                        WorkspaceChangesDiffView(
                            file: file, extras: extras,
                            workspaceId: checkout.workspaceId,
                            mode: compare.mode,
                            baseRef: baseRef)
                    }
                    .navigationDestination(item: $openCommit) { commit in
                        WorkspaceCommitDiffView(commit: commit, actions: gitActions, extras: extras)
                    }
            }
            .task {
                await checkout.loadStatus()
                guard !Task.isCancelled else { return }
                if checkout.status?.hasRemote == true { await extras.loadPrStatus() }
                guard !Task.isCancelled else { return }
                // The panel may open long after `checkout.load()` ran; only subscribe when idle.
                if extras.diffPhase == .idle { await reloadDiff() }
                guard !Task.isCancelled else { return }
                if gitActions.supportsCommitsList { await gitActions.loadCommits() }
                await loadTimeline()
            }
            .onChange(of: compare) { _, _ in
                let previous = diffReload
                diffReload = Task {
                    await previous?.value
                    await reloadDiff()
                }
            }
            .paseoFeedback(.selection, trigger: compare)
        }
    }

    // MARK: Root list

    private var root: some View {
        VStack(spacing: 0) {
            header
            ClaudeDivider()
            if let visibleError {
                errorBanner(visibleError)
            }
            if showsConflictBanner {
                ChangesConflictBanner(title: conflictTitle, conflictFiles: conflictFiles)
            }
            if let forgeIssue {
                ForgeSetupBanner(issue: forgeIssue, remoteHost: forgeRemoteHost)
                    .transition(.opacity)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    WorkspacePRSection(session: session, checkout: checkout)
                    summary
                    if files.isEmpty {
                        listPlaceholder
                    } else {
                        ForEach(files) { file in
                            // One shape per row: the last divider is hidden, not left out.
                            VStack(spacing: 0) {
                                ChangesFileRow(
                                    file: file, cwd: checkout.cwd,
                                    canDiscard: extras.capabilities.supportsDiscardChanges,
                                    onOpen: { openFile = file },
                                    onDiscard: { pendingDiscard = file })
                                ClaudeDivider()
                                    .padding(.leading, 46)
                                    .opacity(file.id == files.last?.id ? 0 : 1)
                            }
                            .id(file.id)
                        }
                        .padding(.bottom, Space.md)
                    }
                    if gitActions.supportsCommitsList {
                        ChangesCommitsSection(gitActions: gitActions, baseRef: baseRef) { commit in
                            openCommit = commit
                        }
                    }
                }
            }
            .refreshable { await reload() }
            actionBar
        }
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: $showCommitSheet) {
            WorkspaceChangesCommitSheet(checkout: checkout) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showBranchSwitcher) {
            WorkspaceBranchSwitcherSheet(
                extras: extras, currentBranch: currentBranch,
                onSwitched: { Task { await reload() } })
        }
        .sheet(isPresented: $showBaseBranchPicker) {
            WorkspaceBaseBranchSheet(
                extras: extras,
                session: session,
                workspaceId: checkout.workspaceId,
                onApplied: { Task { await reload() } })
        }
        .sheet(isPresented: $showCreatePRSheet) {
            WorkspaceCreatePRSheet(
                branch: branchLabel,
                baseRef: baseRef,
                title: $createPRTitle,
                prBody: $createPRBody,
                failure: createPRFailure,
                busy: gitActions.isCreatingPullRequest,
                onCancel: { showCreatePRSheet = false },
                onCreate: { Task { await performCreatePR() } })
        }
        .confirmationDialog(
            "Merge pull request?",
            item: $mergeCandidate,
            titleVisibility: .visible
        ) { method in
            Button(mergeLabel(method), role: .destructive) {
                Task { await performMergePullRequest(method) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { method in
            let number = extras.prBadge?.number.map { "#\($0)" } ?? ""
            let base = extras.prStatus?.baseRefName ?? checkout.prStatus?.baseRefName ?? baseRef ?? "base"
            Text("This merges pull request \(number) into \(base) using \(method.rawValue). This cannot be undone.")
        }
        .confirmationDialog(
            "Discard changes?",
            item: $pendingDiscard,
            titleVisibility: .visible
        ) { file in
            Button("Discard changes", role: .destructive) {
                performDiscard(file)
            }
            Button("Cancel", role: .cancel) {}
        } message: { file in
            // Upstream: workspace.fileActions.confirmRevert.message (en.ts:513).
            Text("Changes to \"\(file.path)\" will be permanently discarded.")
        }
    }

    // MARK: Review drafts

    /// The draft scope for the currently displayed diff.
    private var reviewKey: WorkspaceReviewDraftKey {
        WorkspaceReviewDraftKey(
            workspaceId: checkout.workspaceId,
            mode: compare.mode,
            baseRef: compare == .uncommitted ? "" : (baseRef ?? ""),
            ignoreWhitespace: hideWhitespace)
    }

    // MARK: Header (branch · ahead/behind · PR)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                VStack(alignment: .leading, spacing: 2) {
                    ChangesBranchTitle(label: branchLabel, canSwitch: currentBranch != nil) {
                        showBranchSwitcher = true
                    }
                    HStack(spacing: Space.sm) {
                        if let aheadBehind = checkout.aheadBehind {
                            ChangesAheadBehind(aheadBehind: aheadBehind)
                        }
                        if let badge = extras.prBadge {
                            ChangesPRChip(badge: badge)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if baseRef != nil {
                ChangesCompareSwitch(compare: $compare, baseRef: baseRef)
            }
            ChangesSendFeedbackBar(
                session: session, checkout: checkout, extras: extras, agentId: agentId,
                reviewKey: reviewKey, compare: compare, baseRef: baseRef)
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, 14)
        .padding(.bottom, Space.md)
    }

    // MARK: Summary row

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(files.isEmpty ? "" : "^[\(files.count) file](inflect: true) changed")
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Spacer()
            if !files.isEmpty {
                DiffStat(added: extras.additions, removed: extras.deletions)
            }
        }
        .font(.paseo(.codeSmall))
        .foregroundStyle(Palette.secondaryInk)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.md)
        .padding(.bottom, Space.sm)
    }

    // MARK: List body states

    @ViewBuilder private var listPlaceholder: some View {
        switch extras.diffPhase {
        case .loading, .idle:
            LoadingState("Loading changes…")
                .frame(minHeight: 200)
        case .failed(let message):
            InlineBanner(
                .failure, title: message,
                action: ("Try again", { Task { await reloadDiff() } })
            )
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xl)
        case .ready:
            EmptyState(
                systemImage: "checkmark.circle",
                title: "No changes",
                message: emptySubtitle)
            .frame(minHeight: 200)
        }
    }

    private var emptySubtitle: String {
        switch compare {
        case .uncommitted: "The working tree is clean."
        case .base: baseRef.map { "No differences against \($0)." } ?? "No differences against the base."
        }
    }

    // MARK: Action bar

    private enum PrimaryAction {
        case commit, push, createPR, viewPR
    }

    private var primaryAction: PrimaryAction {
        if checkout.isDirty { return .commit }
        if (checkout.aheadBehind?.ahead ?? 0) > 0 { return .push }
        if extras.prBadge == nil { return .createPR }
        return .viewPR
    }

    /// One quiet primary action, adapting: Commit when dirty, Push when ahead, Create PR when
    /// pushed with no PR open, View PR otherwise. The "…" menu holds the rest.
    private var actionBar: some View {
        VStack(spacing: 0) {
            ClaudeDivider()
            HStack(spacing: 10) {
                primaryButton
                moreMenu
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, 10)
            .padding(.bottom, Space.md)
        }
        .background(Palette.panel)
    }

    @ViewBuilder private var primaryButton: some View {
        switch primaryAction {
        case .commit:
            Button {
                showCommitSheet = true
            } label: {
                Text("Commit").frame(maxWidth: .infinity)
            }
            .buttonStyle(.paseoPrimary(isWorking: checkout.isCommitting))
            .accessibilityLabel("Commit changes")
        case .push:
            Button {
                // The style only blocks touches; assistive activation still reaches this action,
                // and `push()` has no re-entry guard of its own.
                guard !checkout.isPushing else { return }
                Task {
                    let pushed = await checkout.push()
                    if pushed {
                        Haptics.success()
                        showToast("Pushed")
                        await reload()
                    } else {
                        Haptics.failure()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.glyph(.small, weight: .semibold))
                    Text("Push")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.paseoPrimary(isWorking: checkout.isPushing))
            .accessibilityLabel("Push")
        case .createPR:
            Button {
                prepareCreatePR()
            } label: {
                Text("Create PR").frame(maxWidth: .infinity)
            }
            .buttonStyle(.paseoPrimary(isWorking: gitActions.isCreatingPullRequest))
            .accessibilityLabel("Create pull request")
        case .viewPR:
            Button {
                if let url = extras.prBadge.flatMap({ URL(string: $0.url) }),
                    !(extras.prBadge?.url.isEmpty ?? true)
                {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.glyph(.small, weight: .semibold))
                    Text("View PR")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.paseoPrimary())
            .accessibilityLabel("View pull request")
        }
    }

    /// The "…" menu: Pull, Update from <base>, Merge PR (squash/merge/rebase with confirmation),
    /// and the auto-merge toggle when the host supports it. Disabled items carry a one-line reason.
    private var moreMenu: some View {
        Menu {
            Section("Diff options") {
                // Upstream: packages/app/src/git/diff-pane.tsx:842-844; en.ts:983 ("Hide whitespace").
                Toggle("Hide whitespace", isOn: $hideWhitespace).tint(Palette.toggleTint)
                Toggle("Wrap long lines", isOn: $wrapLongLines).tint(Palette.toggleTint)
                Button(collapseAllHunks ? "Expand all files" : "Collapse all files") {
                    collapseAllHunks.toggle()
                }
            }
            gitMenuItem("Pull", reason: pullReason) {
                Task { await performPull() }
            }
            gitMenuItem(updateBaseTitle, reason: baseRef == nil ? "no base branch" : nil) {
                Task { await performMergeFromBase() }
            }
            mergePRMenu
            if gitActions.supportsAutoMerge {
                autoMergeSection
            }
        } label: {
            Label("More git actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.glyph(.regular, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 46, height: 46)
                .background(Palette.chip, in: .circle)
        }
    }

    private func gitMenuItem(
        _ title: String, reason: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(reason.map { "\(title) — \($0)" } ?? title, action: action)
            .disabled(reason != nil)
    }

    private var pullReason: String? {
        checkout.status?.hasRemote == true ? nil : "no remote"
    }

    private var updateBaseTitle: String {
        baseRef.map { "Update from \($0)" } ?? "Update from base"
    }

    private var canMergePR: Bool {
        guard let badge = extras.prBadge else { return false }
        return badge.isOpen && !badge.isMerged
    }

    @ViewBuilder private var mergePRMenu: some View {
        if !canMergePR {
            Button {} label: {
                Text("Merge PR — no open PR")
            }
            .disabled(true)
        } else {
            Menu("Merge PR") {
                Button(mergeLabel(.squash)) { mergeCandidate = .squash }
                Button(mergeLabel(.merge)) { mergeCandidate = .merge }
                Button(mergeLabel(.rebase)) { mergeCandidate = .rebase }
            }
        }
    }

    @ViewBuilder private var autoMergeSection: some View {
        let state = autoMergeState
        Toggle("Auto-merge (squash)", isOn: autoMergeBinding).tint(Palette.toggleTint)
            .disabled(state == nil && extras.prBadge == nil)
    }

    /// Read from the forge facts when the daemon sent them: present object means auto-merge is
    /// armed, explicit null means off, missing key means the daemon didn't say.
    private var autoMergeState: Bool? {
        guard let github = (extras.prStatus?.github ?? checkout.prStatus?.github) else { return nil }
        switch github["autoMergeRequest"] {
        case nil: return nil
        case .some(.null): return false
        case .some: return true
        }
    }

    private var autoMergeBinding: Binding<Bool> {
        Binding(
            get: { autoMergeState ?? false },
            set: { wants in
                Task {
                    let ok = await gitActions.setAutoMerge(enabled: wants, method: wants ? .squash : nil)
                    if ok {
                        Haptics.success()
                        showToast(wants ? "Auto-merge enabled" : "Auto-merge disabled")
                        await reload()
                    } else {
                        Haptics.failure()
                    }
                }
            })
    }

    // MARK: Forge setup callout

    private var forgeIssue: ForgeSetupIssue? {
        // The auth state rides the payload, not the PR: with the CLI missing there is no PR.
        let pr = extras.prStatus ?? checkout.prStatus
        let forge = pr?.forge?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard forge.map({ $0.isEmpty ? "github" : $0 }) ?? "github" == "github" else { return nil }
        let auth = extras.prAuthState ?? checkout.prAuthState
        switch auth {
        case .cliMissing: return .cliMissing
        case .unauthenticated: return .unauthenticated
        default: return nil  // authenticated / no_remote / error / unknown
        }
    }

    /// The remote's hostname for `gh auth login --hostname` on Enterprise hosts.
    private var forgeRemoteHost: String? {
        checkout.status?.remoteUrl.flatMap(ForgeSetupIssue.host(ofRemote:))
    }

    // MARK: Merge conflict banner

    private var conflictFiles: [String] {
        guard showsConflictBanner else { return [] }
        return files.map(\.path)
    }

    private var showsConflictBanner: Bool {
        if gitActions.lastFailure?.code == .mergeConflict { return true }
        return extras.prBadge?.mergeable == .conflicting
    }

    private var conflictTitle: String {
        if gitActions.lastFailure?.code == .mergeConflict {
            let count = conflictFiles.count
            return count > 0
                ? String(
                    AttributedString(
                        localized: "Merge conflict in ^[\(count) file](inflect: true)",
                        bundle: #bundle
                    ).characters)
                : "Merge conflict"
        }
        return "Conflicts with \(baseRef ?? "the base branch")"
    }

    private func performPull() async {
        let ok = await gitActions.pull()
        if ok {
            Haptics.success()
            showToast("Pulled")
            await reload()
        } else {
            Haptics.failure()
            await reload()
        }
    }

    private func performMergeFromBase() async {
        let ok = await gitActions.mergeFromBase()
        if ok {
            Haptics.success()
            showToast("Updated from \(baseRef ?? "base")")
        } else {
            Haptics.failure()
        }
        await reload()
    }

    private func performMergePullRequest(_ method: PullRequestMergeMethod) async {
        let badge = extras.prBadge
        let ok = await gitActions.mergePullRequest(method: method)
        if ok {
            Haptics.success()
            showToast("Merged \(badge?.number.map { "#\($0)" } ?? "")".trimmingCharacters(in: .whitespaces))
        } else {
            Haptics.failure()
        }
        await reload()
    }

    private func prepareCreatePR() {
        let branch = branchLabel
        let lastSubject = gitActions.commits.first?.subject
        createPRTitle = lastSubject ?? "Changes on \(branch)"
        createPRBody = "Changes from \(branch)"
        createPRFailure = nil
        showCreatePRSheet = true
    }

    private func performCreatePR() async {
        let result = await gitActions.createPullRequest(
            title: createPRTitle, body: createPRBody, baseRef: nil)
        guard let result else {
            createPRFailure = gitActions.actionError ?? "The pull request could not be opened."
            return
        }
        showCreatePRSheet = false
        if let url = URL(string: result.url) {
            openURL(url)
        }
        Haptics.success()
        showToast("PR opened \(result.number.map { "#\($0)" } ?? "")".trimmingCharacters(in: .whitespaces))
        await reload()
    }

    private func errorBanner(_ message: String) -> some View {
        InlineBanner(
            .failure, title: message,
            onDismiss: { dismissedError = message })
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.xs)
    }

    // MARK: Actions

    /// Reloads status, PR badge, the diff and the commits list for the current compare selection.
    private func reload() async {
        await checkout.loadStatus()
        if checkout.status?.hasRemote == true { await extras.loadPrStatus() }
        await reloadDiff()
        if gitActions.supportsCommitsList { await gitActions.loadCommits() }
        await loadTimeline()
    }

    private func loadTimeline() async {
        guard let status = extras.prStatus ?? checkout.prStatus,
            let number = status.number,
            let owner = status.repoOwner, let repo = status.repoName
        else { return }
        await timeline.load(prNumber: number, repoOwner: owner, repoName: repo)
    }

    private func reloadDiff() async {
        switch compare {
        case .uncommitted:
            await extras.loadWorkingDiff()
        case .base:
            guard let base = baseRef else { return }
            if extras.capabilities.supportsModernDiff || checkout.supportsDiffAll {
                await extras.loadBaseDiff(baseRef: base)
            } else {
                // Legacy daemon without `checkoutDiffAll`: the branch's committed changes vs the
                // merge base, the closest thing to "vs base" it can express.
                await extras.loadDiff(
                    compare: DiffCompare(
                        cwd: extras.cwd, base: .rev(base), head: .rev("HEAD"), mergeBase: true))
            }
        }
    }

    private func performDiscard(_ file: ParsedDiffFile) {
        Task {
            let discarded = await extras.discard(paths: [file.path])
            if discarded {
                Haptics.light()
                showToast("Discarded \(file.path)")
            } else {
                Haptics.failure()
            }
        }
    }

    private func showToast(_ message: String) {
        toast?.show(message)
    }

    /// Upstream's merge labels (`en.ts:861-863`).
    private func mergeLabel(_ method: PullRequestMergeMethod) -> String {
        switch method {
        case .squash: "Merge PR (squash)"
        case .merge: "Merge PR (merge)"
        case .rebase: "Merge PR (rebase)"
        }
    }

    // MARK: Not a git repository

    private var notGitState: some View {
        EmptyState(
            systemImage: "tray",
            title: "Not a git repository",
            message: "Changes and commits aren't available for this workspace."
        )
        .background(Palette.panel)
    }
}
#endif
