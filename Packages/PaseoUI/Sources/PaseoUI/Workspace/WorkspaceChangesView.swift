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
    /// The workspace id, for the feedback recipients menu (matches session.agents rows).
    var workspaceId: String? = nil

    private enum Compare {
        case uncommitted
        case base
    }

    @State private var compare: Compare = .uncommitted
    @State private var openFile: ParsedDiffFile?
    @State private var openCommit: CheckoutCommit?
    @State private var showCommitSheet = false
    @State private var pendingDiscard: ParsedDiffFile?
    @State private var dismissedError: String?
    @State private var toast: String?
    @State private var showCreatePRSheet = false
    @State private var createPRTitle = ""
    @State private var createPRBody = ""
    @State private var createPRFailure: String?
    @State private var mergeCandidate: PullRequestMergeMethod?
    @State private var showBaseBranchPicker = false
    @State private var showBranchSwitcher = false
    @AppStorage("paseo.diff.hideWhitespace") private var hideWhitespace = false
    @AppStorage("paseo.diff.wrapLongLines") private var wrapLongLines = false
    @AppStorage("paseo.diff.collapseAllHunks") private var collapseAllHunks = false
    @AppStorage("paseo.diff.sideBySide") private var sideBySide = false
    @State private var feedbackError: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.mentionInChat) private var mentionInChat

    private let typography = ClaudeTypography()

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

    private var visibleError: String? {
        let error = extras.actionError ?? checkout.actionError
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
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(item: $openFile) { file in
                        WorkspaceChangesDiffView(
                            file: file, extras: extras,
                            workspaceId: checkout.workspaceId,
                            mode: compare == .uncommitted ? "uncommitted" : "base",
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
                Task { await reloadDiff() }
            }
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
                conflictBanner
            }
            forgeSetupBanner
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        WorkspacePRSection(session: session, checkout: checkout)
                        summary
                        if files.isEmpty {
                            listPlaceholder
                        } else {
                            ForEach(files) { file in
                                fileRow(file)
                                    .id(file.id)
                                if file.id != files.last?.id {
                                    ClaudeDivider().padding(.leading, 46)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        if gitActions.supportsCommitsList {
                            commitsSection
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if files.count >= 3 {
                        Menu {
                            ForEach(files) { file in
                                Button(shortFileName(file.path)) {
                                    Haptics.selection()
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                                        proxy.scrollTo(file.id, anchor: .top)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(ClaudePalette.ink)
                                .frame(width: 44, height: 44)
                                .glassEffect()
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 20)
                        .accessibilityLabel("Jump to file")
                    }
                }
            }
            .refreshable { await reload() }
            actionBar
        }
        .background(ClaudePalette.panel)
        .foregroundStyle(ClaudePalette.ink)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .padding(.bottom, 96)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
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
            isPresented: Binding(
                get: { mergeCandidate != nil },
                set: { if !$0 { mergeCandidate = nil } }),
            titleVisibility: .visible
        ) {
            let method = mergeCandidate ?? .squash
            Button("Merge (\(method.rawValue))", role: .destructive) {
                mergeCandidate = nil
                Task { await performMergePullRequest(method) }
            }
            Button("Cancel", role: .cancel) { mergeCandidate = nil }
        } message: {
            let method = mergeCandidate ?? .squash
            let number = extras.prBadge?.number.map { "#\($0)" } ?? ""
            let base = extras.prStatus?.baseRefName ?? checkout.prStatus?.baseRefName ?? baseRef ?? "base"
            Text("This merges pull request \(number) into \(base) using \(method.rawValue). This cannot be undone.")
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                guard let target = pendingDiscard else { return }
                pendingDiscard = nil
                performDiscard(target)
            }
            Button("Cancel", role: .cancel) { pendingDiscard = nil }
        } message: {
            Text(
                pendingDiscard.map {
                    "This removes all changes in \($0.path), staged and unstaged. This cannot be undone."
                } ?? ""
            )
        }
    }

    // MARK: Send feedback (N)

    /// The draft scope for the currently displayed diff.
    private var reviewKey: WorkspaceReviewDraftKey {
        WorkspaceReviewDraftKey(
            workspaceId: checkout.workspaceId,
            mode: compare == .uncommitted ? "uncommitted" : "base",
            baseRef: compare == .uncommitted ? "" : (baseRef ?? ""),
            ignoreWhitespace: hideWhitespace)
    }

    /// Review drafts that live on the currently displayed diff.
    private var reviewDraftCount: Int {
        WorkspaceReviewDrafts.shared.count(for: reviewKey)
    }

    /// Drafts whose anchor is gone from the current diff (M3k follow-up): invisible in the
    /// diff, skipped by the attachment builder. Only meaningful once the diff is ready —
    /// before that, an empty file list would make every draft look stale.
    private var staleReviewDrafts: [WorkspaceReviewDraftComment] {
        guard extras.diffPhase == .ready else { return [] }
        let scoped = WorkspaceReviewDrafts.shared.comments(for: reviewKey)
        guard !scoped.isEmpty else { return [] }
        let built = WorkspaceReviewAttachmentBuilder.buildAll(
            comments: scoped, files: extras.files, cwd: checkout.cwd,
            mode: compare == .uncommitted ? "uncommitted" : "base",
            baseRef: baseRef)
        let sentIds = Set((built?.1 ?? []).map(\.id))
        return scoped.filter { !sentIds.contains($0.id) }
    }

    /// The agents in this workspace; the open chat's agent is the default recipient.
    private var feedbackRecipients: [AgentSnapshot] {
        session.agents.filter { $0.workspaceId == checkout.workspaceId }
    }

    private var defaultFeedbackRecipient: AgentSnapshot? {
        let all = feedbackRecipients
        if let agentId, let current = all.first(where: { $0.id == agentId }) { return current }
        return all.first
    }

    @ViewBuilder private var sendFeedbackBar: some View {
        if reviewDraftCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let defaultRecipient = defaultFeedbackRecipient {
                    HStack(spacing: 0) {
                        Button {
                            Task { await sendFeedback(to: defaultRecipient) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Send feedback (\(PaseoFormat.integer(reviewDraftCount)))")
                                    .font(typography.sans(13, weight: .semibold))
                            }
                            .foregroundStyle(ClaudePalette.background)
                            .padding(.leading, 14)
                            .padding(.trailing, 12)
                            .frame(height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Send feedback to \(agentTitle(defaultRecipient)), \(reviewDraftCount) comments")
                        if feedbackRecipients.count > 1 {
                            Menu {
                                ForEach(feedbackRecipients) { agent in
                                    Button {
                                        Task { await sendFeedback(to: agent) }
                                    } label: {
                                        if agent.id == agentId {
                                            Label(
                                                "\(agentTitle(agent)) (this chat)",
                                                systemImage: "checkmark")
                                        } else {
                                            Text(agentTitle(agent))
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ClaudePalette.background)
                                    .frame(height: 34)
                                    .padding(.trailing, 10)
                            }
                            .accessibilityLabel("Choose an agent to send feedback")
                        }
                    }
                    .background(ClaudePalette.ink, in: .capsule)
                } else {
                    Text("Open an agent in this workspace to send feedback.")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                if let feedbackError {
                    Text(feedbackError)
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                }
            }
            .padding(.top, 2)
            if !staleReviewDrafts.isEmpty {
                HStack(spacing: 6) {
                    Text("\(PaseoFormat.integer(staleReviewDrafts.count)) comments no longer match this diff")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Button("Clear") {
                        Haptics.selection()
                        for stale in staleReviewDrafts {
                            WorkspaceReviewDrafts.shared.delete(key: reviewKey, id: stale.id)
                        }
                    }
                    .font(typography.sans(12, weight: .medium))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear stale comments")
                    .accessibilityIdentifier("changes.staleDrafts.clear")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(staleReviewDrafts.count) comments no longer match this diff")
            }
            }
        }
    }

    private func agentTitle(_ agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.map { $0.isEmpty ? "Agent" : $0 } ?? "Agent"
    }

    /// Sends the current diff's drafts as one `review` attachment on one prompt — the open
    /// chat's agent by default, otherwise the picked workspace agent. Drafts that were
    /// attached are cleared only when the daemon accepts the message.
    private func sendFeedback(to agent: AgentSnapshot) async {
        feedbackError = nil
        let scoped = WorkspaceReviewDrafts.shared.comments(for: reviewKey)
        guard !scoped.isEmpty else { return }
        guard let (attachment, sent) = WorkspaceReviewAttachmentBuilder.buildAll(
            comments: scoped, files: extras.files, cwd: checkout.cwd,
            mode: compare == .uncommitted ? "uncommitted" : "base",
            baseRef: baseRef)
        else {
            feedbackError = "Saved comments no longer match this diff."
            Haptics.failure()
            return
        }
        let conversation = session.conversation(for: agent.id)
        await conversation.sendWithAttachments(
            "Please address this code review.",
            attachments: [.review(attachment)])
        if let error = conversation.actionError {
            feedbackError = error
            Haptics.failure()
            return
        }
        WorkspaceReviewDrafts.shared.clearSent(key: reviewKey, comments: sent)
        feedbackError = nil
        Haptics.success()
        showToast("Feedback sent to \(agentTitle(agent))")
    }

    // MARK: Header (branch · ahead/behind · PR)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                VStack(alignment: .leading, spacing: 2) {
                    branchTitle
                    HStack(spacing: 8) {
                        aheadBehind
                        pullRequestChip
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh changes")
            }
            if baseRef != nil {
                compareSwitch
            }
            sendFeedbackBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// The branch name, tapping which opens the switcher (upstream `BranchSwitcher`'s trigger,
    /// `branch-switcher.tsx`). Only the name is the button: the PR chip beside/below it is its own
    /// button. A detached HEAD has no branch to switch to and stays a plain label.
    @ViewBuilder private var branchTitle: some View {
        if currentBranch != nil {
            Button {
                Haptics.selection()
                showBranchSwitcher = true
            } label: {
                HStack(spacing: 6) {
                    Text(branchLabel)
                        .font(typography.mono(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current branch: \(branchLabel). Press to switch branch.")
            .accessibilityIdentifier("changes.branchSwitcher")
        } else {
            Text(branchLabel)
                .font(typography.mono(13, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var aheadBehind: some View {
        if let aheadBehind = checkout.aheadBehind {
            if aheadBehind.ahead > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                    Text("\(PaseoFormat.integer(aheadBehind.ahead))").font(typography.mono(12))
                }
                .foregroundStyle(ClaudePalette.secondaryInk)
                .accessibilityLabel("\(aheadBehind.ahead) commits ahead")
            }
            if aheadBehind.behind > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                    Text("\(PaseoFormat.integer(aheadBehind.behind))").font(typography.mono(12))
                }
                .foregroundStyle(ClaudePalette.secondaryInk)
                .accessibilityLabel("\(aheadBehind.behind) commits behind")
            }
        }
    }

    @ViewBuilder private var pullRequestChip: some View {
        if let badge = extras.prBadge {
            let tint = badgeTint(badge)
            Button {
                if let url = URL(string: badge.url), !badge.url.isEmpty {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 5) {
                    if badge.isOpen {
                        Circle().fill(checksTint(badge.checks)).frame(width: 7, height: 7)
                    }
                    Text(badgeLabel(badge))
                        .font(typography.sans(11, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(tint)
                .background(tint.opacity(0.14), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pull request \(badgeLabel(badge))")
        }
    }

    private func badgeTint(_ badge: PullRequestBadge) -> Color {
        if badge.isDraft, badge.isOpen { return ClaudePalette.secondaryInk }
        if badge.isMerged { return ClaudePalette.unread }
        if badge.isOpen { return ClaudePalette.successInk }
        return ClaudePalette.tertiaryInk
    }

    private func checksTint(_ checks: PullRequestBadge.Checks) -> Color {
        switch checks {
        case .passing: ClaudePalette.successInk
        case .failing: ClaudePalette.failureInk
        case .pending: ClaudePalette.warning
        case .none, .unknown: ClaudePalette.secondaryInk
        }
    }

    private func badgeLabel(_ badge: PullRequestBadge) -> String {
        let number = badge.number.map { "#\($0)" } ?? "PR"
        if badge.isDraft, badge.isOpen { return "\(number) · Draft" }
        if badge.isMerged { return "\(number) · Merged" }
        if badge.isOpen { return number }
        return "\(number) · Closed"
    }

    /// Chip-style compare switch; only offered when the status carries a base ref.
    private var compareSwitch: some View {
        HStack(spacing: 2) {
            compareSegment(.uncommitted, label: "Uncommitted")
            compareSegment(.base, label: baseRef.map { "vs \($0)" } ?? "vs base")
        }
        .padding(2)
        .background(ClaudePalette.chip, in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compareSegment(_ value: Compare, label: String) -> some View {
        let selected = compare == value
        return Button {
            guard compare != value else { return }
            Haptics.selection()
            compare = value
        } label: {
            Text(label)
                .font(typography.sans(12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .foregroundStyle(selected ? ClaudePalette.background : ClaudePalette.secondaryInk)
                .background(selected ? ClaudePalette.ink : Color.clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "")
    }

    // MARK: Summary row

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(files.isEmpty ? "" : "\(files.count) \(files.count == 1 ? "file" : "files") changed")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Spacer()
            if !files.isEmpty {
                Text("+\(PaseoFormat.integer(extras.additions))")
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(PaseoFormat.integer(extras.deletions))")
                    .foregroundStyle(ClaudePalette.failureInk)
            }
        }
        .font(typography.mono(12))
        .foregroundStyle(ClaudePalette.secondaryInk)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: List body states

    @ViewBuilder private var listPlaceholder: some View {
        switch extras.diffPhase {
        case .loading, .idle:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading changes…")
                    .font(typography.sans(14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(ClaudePalette.failureInk)
                Text(message)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    Task { await reloadDiff() }
                } label: {
                    Text("Retry")
                        .font(typography.sans(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(ClaudePalette.chip, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
        case .ready:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                Text("No changes")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(emptySubtitle)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
        }
    }

    private var emptySubtitle: String {
        switch compare {
        case .uncommitted: "The working tree is clean."
        case .base: baseRef.map { "No differences against \($0)." } ?? "No differences against the base."
        }
    }

    // MARK: File rows

    private func fileRow(_ file: ParsedDiffFile) -> some View {
        let style = statusStyle(for: file)
        return Button {
            Haptics.selection()
            openFile = file
        } label: {
            HStack(spacing: 12) {
                Text(style.letter)
                    .font(typography.mono(11, weight: .semibold))
                    .foregroundStyle(style.tint)
                    .frame(width: 22, height: 22)
                    .background(style.tint.opacity(0.16), in: .rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(typography.mono(12.5))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let oldPath = file.oldPath {
                        Text("from \(oldPath)")
                            .font(typography.mono(10))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(PaseoFormat.integer(file.additions))")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(PaseoFormat.integer(file.deletions))")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
            .draggable(file.path)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.word) \(file.path), plus \(file.additions), minus \(file.deletions)")
        .contextMenu {
            Button("Copy path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = (checkout.cwd as NSString)
                    .appendingPathComponent(file.path)
                showToast("Path copied")
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = file.path
                showToast("Relative path copied")
            }
            if extras.capabilities.supportsDiscardChanges {
                Button("Discard changes…", systemImage: "trash", role: .destructive) {
                    pendingDiscard = file
                }
            }
        }
    }

    private func shortFileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func statusStyle(for file: ParsedDiffFile) -> (letter: String, tint: Color, word: String) {
        if file.oldPath != nil { return ("R", ClaudePalette.unread, "Renamed") }
        if file.isNew { return ("A", ClaudePalette.successInk, "Added") }
        if file.isDeleted { return ("D", ClaudePalette.failureInk, "Deleted") }
        return ("M", ClaudePalette.warning, "Modified")
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
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(ClaudePalette.panel)
    }

    @ViewBuilder private var primaryButton: some View {
        switch primaryAction {
        case .commit:
            Button {
                showCommitSheet = true
            } label: {
                if checkout.isCommitting {
                    ProgressView().tint(ClaudePalette.background)
                        .frame(maxWidth: .infinity).frame(height: 46)
                } else {
                    Text("Commit")
                        .font(typography.sans(15, weight: .semibold))
                        .foregroundStyle(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
            }
            .background(ClaudePalette.ink, in: .capsule)
            .disabled(checkout.isCommitting)
            .accessibilityLabel("Commit changes")
        case .push:
            Button {
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
                if checkout.isPushing {
                    ProgressView().tint(ClaudePalette.background)
                        .frame(maxWidth: .infinity).frame(height: 46)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Push")
                            .font(typography.sans(15, weight: .semibold))
                    }
                    .foregroundStyle(ClaudePalette.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
            }
            .background(ClaudePalette.ink, in: .capsule)
            .disabled(checkout.isPushing)
            .accessibilityLabel("Push")
        case .createPR:
            Button {
                Haptics.selection()
                prepareCreatePR()
            } label: {
                if gitActions.isCreatingPullRequest {
                    ProgressView().tint(ClaudePalette.background)
                        .frame(maxWidth: .infinity).frame(height: 46)
                } else {
                    Text("Create PR")
                        .font(typography.sans(15, weight: .semibold))
                        .foregroundStyle(ClaudePalette.background)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
            }
            .background(ClaudePalette.ink, in: .capsule)
            .disabled(gitActions.isCreatingPullRequest)
            .accessibilityLabel("Create pull request")
        case .viewPR:
            Button {
                Haptics.selection()
                if let url = extras.prBadge.flatMap({ URL(string: $0.url) }),
                    !(extras.prBadge?.url.isEmpty ?? true)
                {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                    Text("View PR")
                        .font(typography.sans(15, weight: .semibold))
                }
                .foregroundStyle(ClaudePalette.background)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .background(ClaudePalette.ink, in: .capsule)
            .accessibilityLabel("View pull request")
        }
    }

    /// The "…" menu: Pull, Update from <base>, Merge PR (squash/merge/rebase with confirmation),
    /// and the auto-merge toggle when the host supports it. Disabled items carry a one-line reason.
    private var moreMenu: some View {
        Menu {
            Section("Diff options") {
                if horizontalSizeClass == .regular {
                    Toggle("Side by side", isOn: $sideBySide).tint(.blue)
                }
                Toggle("Hide whitespace changes", isOn: $hideWhitespace).tint(.blue)
                Toggle("Wrap long lines", isOn: $wrapLongLines).tint(.blue)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .frame(width: 46, height: 46)
                .background(ClaudePalette.chip, in: .circle)
        }
        .accessibilityLabel("More git actions")
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
                Button("Merge (squash)") { mergeCandidate = .squash }
                Button("Merge (merge)") { mergeCandidate = .merge }
                Button("Merge (rebase)") { mergeCandidate = .rebase }
            }
        }
    }

    @ViewBuilder private var autoMergeSection: some View {
        let state = autoMergeState
        Toggle("Auto-merge (squash)", isOn: autoMergeBinding).tint(.blue)
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

    /// The precise forge setup step this host is missing, when the daemon reports it on the PR
    /// status payload (`authState`). GitHub-only: the commands are gh-specific, and guessing
    /// another forge's installer would be wrong. Copy-only; nothing is run remotely.
    private enum ForgeIssue {
        case cliMissing
        case unauthenticated

        var title: String {
            switch self {
            case .cliMissing: "GitHub CLI isn't installed on this host"
            case .unauthenticated: "GitHub CLI isn't authenticated on this host"
            }
        }
    }

    private var forgeIssue: ForgeIssue? {
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

    /// The remote's hostname for `gh auth login --hostname` on Enterprise hosts; "github.com" is
    /// dropped because plain `gh auth login` targets it.
    private var forgeRemoteHost: String? {
        guard let remote = checkout.status?.remoteUrl else { return nil }
        var s = remote
        for prefix in ["ssh://", "https://", "http://", "git@"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let end = s.firstIndex(where: { $0 == "/" || $0 == ":" }) {
            s = String(s[..<end])
        }
        let host = s.trimmingCharacters(in: .whitespaces)
        return host.isEmpty ? nil : host
    }

    private func forgeCommands(for issue: ForgeIssue) -> [String] {
        switch issue {
        case .cliMissing:
            return ["brew install gh", "sudo apt install gh", "gh auth login"]
        case .unauthenticated:
            if let host = forgeRemoteHost, host != "github.com" {
                return ["gh auth login --hostname \(host)"]
            }
            return ["gh auth login"]
        }
    }

    @ViewBuilder private var forgeSetupBanner: some View {
        if let issue = forgeIssue {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.warning)
                VStack(alignment: .leading, spacing: 6) {
                    Text(issue.title)
                        .font(typography.sans(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                    Text("Run this on the host, then refresh:")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    ForEach(forgeCommands(for: issue), id: \.self) { command in
                        forgeCopyCommand(command)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ClaudePalette.warning.opacity(0.08))
            .transition(.opacity)
        }
    }

    @State private var copiedForgeCommand: String?

    private func forgeCopyCommand(_ command: String) -> some View {
        Button {
            UIPasteboard.general.string = command
            Haptics.success()
            copiedForgeCommand = command
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedForgeCommand == command { copiedForgeCommand = nil }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: copiedForgeCommand == command ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                Text(command)
                    .font(typography.mono(12))
                    .lineLimit(1)
            }
            .foregroundStyle(ClaudePalette.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(ClaudePalette.chip, in: .capsule)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(command)")
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

    private var conflictBanner: some View {
        let count = conflictFiles.count
        let title: String = {
            if gitActions.lastFailure?.code == .mergeConflict {
                return count > 0
                    ? "Merge conflict in \(count) \(count == 1 ? "file" : "files")"
                    : "Merge conflict"
            }
            return "Conflicts with \(baseRef ?? "the base branch")"
        }()
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ClaudePalette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(typography.sans(12, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text("Ask the agent to resolve it.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !conflictFiles.isEmpty, let mentionInChat {
                Button {
                    Haptics.selection()
                    for path in conflictFiles.prefix(10) {
                        mentionInChat(path)
                    }
                } label: {
                    Text("Ask the agent")
                        .font(typography.sans(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.background)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(ClaudePalette.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mention the conflicted files in chat")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ClaudePalette.warning.opacity(0.08))
    }

    // MARK: Commits section

    /// "Commits ahead of <base>" rows, behind the `commitsList` gate. Tapping a row opens the
    /// commit's files; each file opens the shared diff view without the discard affordance.
    @ViewBuilder private var commitsSection: some View {
        if !gitActions.commits.isEmpty || gitActions.commitsError != nil {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Commits ahead of \(baseRef ?? "base")")
                        .font(typography.sans(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Spacer(minLength: 8)
                    if !gitActions.commits.isEmpty {
                        Text("\(PaseoFormat.integer(gitActions.commits.count))")
                            .font(typography.mono(12))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                if let message = gitActions.commitsError {
                    Text(message)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                } else {
                    ForEach(gitActions.commits) { commit in
                        commitRow(commit)
                        if commit.id != gitActions.commits.last?.id {
                            ClaudeDivider().padding(.leading, 20)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func commitRow(_ commit: CheckoutCommit) -> some View {
        Button {
            Haptics.selection()
            openCommit = commit
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(commit.shortSha)
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                        Text("· \(relativeAge(commit.authorDate))")
                            .font(typography.sans(11))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Commit \(commit.shortSha), \(commit.subject)")
    }

    private func relativeAge(_ iso: String) -> String {
        guard let date = PaseoDate.parse(iso) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(ClaudePalette.failureInk)
            Text(message)
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.failureInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismissedError = message
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ClaudePalette.failureInk.opacity(0.08))
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
                Haptics.success()
                showToast("Discarded \(file.path)")
            } else {
                Haptics.failure()
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback)) {
            toast = message
        }
        let shown = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == shown {
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback)) {
                    toast = nil
                }
            }
        }
    }

    // MARK: Not a git repository

    private var notGitState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text("Not a git repository")
                .font(typography.sans(16, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("Changes and commits aren't available for this workspace.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClaudePalette.panel)
    }
}
#endif
