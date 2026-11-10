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
/// side; the message it returns ("… uncommitted changes. Commit or stash before switching
/// branches.") is shown as-is. Upstream follows that error with a stash-and-switch dialog; this
/// client has no stash RPC (`branch-switcher-operations.ts` uses `stashList`/`stashSave`), so the
/// daemon's instruction is the whole story here.
struct WorkspaceBranchSwitcherSheet: View {
    let extras: WorkspaceGitExtras
    /// The branch the workspace is on; nil for a detached HEAD (upstream hides the trigger then).
    let currentBranch: String?
    /// Called after a successful switch so the page can re-read the git state.
    var onSwitched: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var hasLoaded = false
    @State private var switchError: String?
    @State private var switchingTo: String?


    /// The current branch checked first? No: upstream keeps the daemon's order and only marks the
    /// selected row, so the list does not jump under the user's finger.
    private var branches: [BranchSuggestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return extras.branchSuggestions }
        return extras.branchSuggestions.filter { $0.name.lowercased().contains(query) }
    }

    private var isBusy: Bool { switchingTo != nil }

    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Switch branch", close: { dismiss() })
            searchField
            if let switchError {
                Text(switchError)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("branchSwitcher.error")
            }
            content
                .frame(maxHeight: .infinity)
            Spacer(minLength: 8)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            guard !hasLoaded else { return }
            // One page, like upstream's `getBranchSuggestions(200)`.
            await extras.loadBranchSuggestions(limit: 200)
            hasLoaded = true
        }
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
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Palette.chip, in: .capsule)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        if !hasLoaded && extras.branchSuggestions.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let branchError = extras.branchError, extras.branchSuggestions.isEmpty {
            // Upstream `branchSwitcher.failedToLoad`.
            Text("Could not load branches. Reopen the picker to try again.")
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.failureInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text("Could not load branches. Reopen the picker to try again.")
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    /// Upstream `branchSwitcher.empty`, also shown when the search filters everything out — the
    /// Combobox uses the same string for both.
    private var emptyState: some View {
        Text("No branches found.")
            .font(.paseo(.callout))
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    ProgressView().controlSize(.small)
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

    /// Upstream `handleBranchSelect`: picking the branch you are on does nothing; a daemon
    /// rejection is shown as-is; `failedToSwitch` covers a transport failure. Haptics on the pick,
    /// spinner until the switch lands (`isSwitchingBranch`).
    private func switchTo(_ name: String) {
        guard !isBusy, name != currentBranch else { return }
        Haptics.selection()
        switchError = nil
        switchingTo = name
        Task {
            let switched = await extras.switchBranch(name)
            switchingTo = nil
            if switched {
                Haptics.success()
                onSwitched()
                dismiss()
            } else {
                Haptics.failure()
                switchError = extras.actionError ?? "Failed to switch branch"
            }
        }
    }
}
#endif
