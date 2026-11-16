#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The branch switcher: tapping the branch name in the Changes header opens this searchable list
/// of branches, with the current one checked (upstream `components/branch-switcher.tsx` over
/// `hooks/use-branch-switcher.ts`).
///
/// Upstream loads one page of branch names (`getBranchSuggestions(200)`) and filters them in the
/// picker, so search never hits the daemon. A dirty working tree blocks the switch on the daemon
/// side; when the daemon's message says the tree has uncommitted changes, upstream offers
/// "Stash & Switch" instead of the error (`use-branch-switcher.ts:124-171`), and after a switch it
/// offers to restore a stash Paseo left on the branch being entered (`:96-122`).
/// `stashList` / `stashSave` / `stashPop` live in `branch-switcher-operations.ts:9-11`;
/// the dialog words are `en.ts` `branchSwitcher.*`.
struct WorkspaceBranchSwitcherSheet: View {
    let extras: WorkspaceGitExtras
    /// The branch the workspace is on; nil for a detached HEAD (upstream hides the trigger then).
    let currentBranch: String?
    /// Called after a successful switch so the page can re-read the git state.
    var onSwitched: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toast) private var toast
    @State private var searchText = ""
    @State private var hasLoaded = false
    @State private var switchError: String?
    @State private var switchingTo: String?
    /// The branch the "Uncommitted changes" dialog would stash for.
    @State private var pendingStashSwitch: String?
    /// The stash Paseo left on the branch just entered, offered for restoring.
    @State private var pendingRestore: StashEntry?
    @State private var isRestoring = false

    /// The current branch checked first? No: upstream keeps the daemon's order and only marks the
    /// selected row, so the list does not jump under the user's finger.
    private var branches: [BranchSuggestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return extras.branchSuggestions }
        return extras.branchSuggestions.filter { $0.name.lowercased().contains(query) }
    }

    private var isBusy: Bool { switchingTo != nil || isRestoring }

    var body: some View {
        SheetScaffold("Switch branch", detents: .mediumLarge) {
            VStack(spacing: Space.md) {
                searchField
                if let switchError {
                    InlineBanner(.failure, title: switchError)
                        .padding(.horizontal, Space.lg)
                        .accessibilityIdentifier("branchSwitcher.error")
                }
                content
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            guard !hasLoaded else { return }
            // One page, like upstream's `getBranchSuggestions(200)`.
            await extras.loadBranchSuggestions(limit: 200)
            hasLoaded = true
        }
        .alert("Uncommitted changes", isPresented: stashPromptBinding) {
            Button("Stash & Switch") {
                if let branch = pendingStashSwitch { stashAndSwitch(to: branch) }
            }
            Button("Cancel", role: .cancel) { pendingStashSwitch = nil }
        } message: {
            Text("You have uncommitted changes. Stash them before switching branches?")
        }
        .alert("Restore stashed changes?", isPresented: restorePromptBinding) {
            Button("Restore") {
                if let stash = pendingRestore { restoreStash(stash) }
            }
            Button("Later", role: .cancel) {
                pendingRestore = nil
                completeSwitch()
            }
        } message: {
            Text(
                "This branch has stashed changes from a previous session. Would you like to restore them?"
            )
        }
    }

    private var stashPromptBinding: Binding<Bool> {
        Binding(
            get: { pendingStashSwitch != nil },
            set: { if !$0 { pendingStashSwitch = nil } })
    }

    private var restorePromptBinding: Binding<Bool> {
        Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } })
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Filter branches...", text: $searchText)
                .font(.paseo(.callout))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if isBusy {
                InlineProgress()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Palette.chip, in: .capsule)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        if !hasLoaded && extras.branchSuggestions.isEmpty {
            LoadingState()
        } else if let branchError = extras.branchError, extras.branchSuggestions.isEmpty {
            // Upstream `branchSwitcher.failedToLoad`.
            InlineBanner(
                .failure, title: "Could not load branches. Reopen the picker to try again."
            )
            .padding(.horizontal, Space.xl)
            .frame(maxHeight: .infinity)
            .accessibilityHint(Text(branchError))
        } else if branches.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(branches, id: \.name) { branch in
                            branchRow(branch)
                            ClaudeDivider().padding(.leading, 52)
                        }
                    }
                }
                // Upstream keeps a footer under the options when the last read failed
                // (`branch-switcher.tsx`, `errorFooter`).
                if extras.branchError != nil {
                    InlineBanner(
                        .failure, title: "Could not load branches. Reopen the picker to try again."
                    )
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    /// Upstream `branchSwitcher.empty`, also shown when the search filters everything out — the
    /// Combobox uses the same string for both.
    private var emptyState: some View {
        EmptyState(title: "No branches found.")
    }

    private func branchRow(_ branch: BranchSuggestion) -> some View {
        let current = branch.name == currentBranch
        return Button {
            switchTo(branch.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 20)
                Text(branch.name)
                    .font(.paseo(.code, weight: current ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if switchingTo == branch.name {
                    InlineProgress()
                } else if current {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Current branch")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(
            current ? "\(branch.name), current branch" : "Switch to \(branch.name)")
        .accessibilityIdentifier("branchSwitcher.branch")
    }

    /// Upstream `handleBranchSelect`: picking the branch you are on does nothing; a dirty tree gets
    /// the stash dialog (`use-branch-switcher.ts:164-168`); any other daemon rejection is shown
    /// as-is, and `failedToSwitch` covers a transport failure. Haptics on the pick, spinner until
    /// the switch lands (`isSwitchingBranch`).
    private func switchTo(_ name: String) {
        guard !isBusy, name != currentBranch else { return }
        switchError = nil
        switchingTo = name
        Task {
            let switched = await extras.switchBranch(name)
            switchingTo = nil
            guard switched else {
                Haptics.failure()
                if extras.lastSwitchBlockedByChanges {
                    pendingStashSwitch = name
                } else {
                    switchError = extras.actionError ?? "Failed to switch branch"
                }
                return
            }
            await maybeOfferRestore(on: name)
        }
    }

    /// After a switch lands, upstream lists the Paseo stashes and offers to restore the one tagged
    /// with the branch just entered (`use-branch-switcher.ts:96-122`).
    private func maybeOfferRestore(on name: String) async {
        await extras.loadPaseoStashes()
        if let stash = extras.paseoStash(forBranch: name) {
            pendingRestore = stash
            return
        }
        completeSwitch()
    }

    /// `stashAndSwitch`: save the dirty tree under the current branch, then switch
    /// (`use-branch-switcher.ts:124-153`). Upstream offers no restore prompt on this path.
    private func stashAndSwitch(to name: String) {
        pendingStashSwitch = nil
        switchError = nil
        switchingTo = name
        Task {
            let switched = await extras.stashAndSwitch(to: name)
            switchingTo = nil
            if switched {
                completeSwitch()
            } else {
                Haptics.failure()
                switchError = extras.actionError ?? "Failed to switch branch"
            }
        }
    }

    /// Restores the stashed entry, then finishes the switch. Upstream reports the outcome with a
    /// toast and leaves the branch switched either way (`use-branch-switcher.ts:110-116`).
    private func restoreStash(_ stash: StashEntry) {
        pendingRestore = nil
        isRestoring = true
        Task {
            let restored = await extras.popStash(index: stash.index)
            isRestoring = false
            if restored {
                Haptics.success()
                toast?.show("Stashed changes restored")
            } else {
                Haptics.failure()
                toast?.show(extras.actionError ?? "The restore failed.")
            }
            onSwitched()
            dismiss()
        }
    }

    private func completeSwitch() {
        Haptics.success()
        onSwitched()
        dismiss()
    }
}
#endif
