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

    private enum Compare {
        case uncommitted
        case base
    }

    @State private var compare: Compare = .uncommitted
    @State private var openFile: ParsedDiffFile?
    @State private var showCommitSheet = false
    @State private var pendingDiscard: ParsedDiffFile?
    @State private var dismissedError: String?
    @State private var toast: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private let typography = ClaudeTypography()

    /// The modern-diff helper for this checkout. Idempotent: the same instance is returned while
    /// the workspace is open. Created through the store (never constructed by hand).
    private var extras: WorkspaceGitExtras {
        session.gitExtras.workspace(for: checkout)
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
        extras.currentBranch ?? checkout.branch ?? "Detached HEAD"
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
                        WorkspaceChangesDiffView(file: file, extras: extras)
                    }
            }
            .task {
                await checkout.loadStatus()
                if checkout.status?.hasRemote == true { await extras.loadPrStatus() }
                // The panel may open long after `checkout.load()` ran; only subscribe when idle.
                if extras.diffPhase == .idle { await reloadDiff() }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary
                    if files.isEmpty {
                        listPlaceholder
                    } else {
                        ForEach(files) { file in
                            fileRow(file)
                            if file.id != files.last?.id {
                                ClaudeDivider().padding(.leading, 46)
                            }
                        }
                        .padding(.bottom, 12)
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

    // MARK: Header (branch · ahead/behind · PR)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branchLabel)
                        .font(typography.mono(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var aheadBehind: some View {
        if let aheadBehind = checkout.aheadBehind {
            if aheadBehind.ahead > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                    Text("\(aheadBehind.ahead)").font(typography.mono(12))
                }
                .foregroundStyle(ClaudePalette.secondaryInk)
                .accessibilityLabel("\(aheadBehind.ahead) commits ahead")
            }
            if aheadBehind.behind > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down").font(.system(size: 10, weight: .semibold))
                    Text("\(aheadBehind.behind)").font(typography.mono(12))
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
                Text("+\(extras.additions)")
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(extras.deletions)")
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
                Button("Try again") { Task { await reloadDiff() } }
                    .font(typography.sans(14, weight: .medium))
                    .buttonStyle(.bordered)
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
                Text("+\(file.additions)")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(file.deletions)")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
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

    private func statusStyle(for file: ParsedDiffFile) -> (letter: String, tint: Color, word: String) {
        if file.oldPath != nil { return ("R", ClaudePalette.unread, "Renamed") }
        if file.isNew { return ("A", ClaudePalette.successInk, "Added") }
        if file.isDeleted { return ("D", ClaudePalette.failureInk, "Deleted") }
        return ("M", ClaudePalette.warning, "Modified")
    }

    // MARK: Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            ClaudeDivider()
            HStack(spacing: 10) {
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
                .background(ClaudePalette.ink.opacity(checkout.isDirty ? 1 : 0.35), in: .capsule)
                .disabled(!checkout.isDirty || checkout.isCommitting)
                .accessibilityLabel("Commit changes")

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
                        ProgressView().tint(ClaudePalette.ink)
                            .frame(width: 96, height: 46)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Push")
                                .font(typography.sans(15, weight: .semibold))
                        }
                        .foregroundStyle(ClaudePalette.ink)
                        .frame(width: 96, height: 46)
                    }
                }
                .background(ClaudePalette.chip, in: .capsule)
                .disabled(checkout.isPushing)
                .accessibilityLabel("Push")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(ClaudePalette.panel)
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

    /// Reloads status, PR badge and the diff for the current compare selection.
    private func reload() async {
        await checkout.loadStatus()
        if checkout.status?.hasRemote == true { await extras.loadPrStatus() }
        await reloadDiff()
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
