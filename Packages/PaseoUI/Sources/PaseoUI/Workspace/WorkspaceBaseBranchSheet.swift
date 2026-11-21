#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Searchable base-branch picker backed by the T11 branch suggestions. Applies with a full ref
/// (`refs/heads/<name>` for local, `refs/remotes/<name>` for remote-only) and calls `onApplied`
/// so the page can refresh diff and ahead/behind.
struct WorkspaceBaseBranchSheet: View {
    let extras: WorkspaceGitExtras
    let session: HostSession
    let workspaceId: String
    var onApplied: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    /// The branch being applied; only its row shows the spinner.
    @State private var applyingName: String?
    @State private var applyError: String?
    @State private var hasLoaded = false


    private var suggestions: [BranchSuggestion] { extras.branchSuggestions }

    private var isApplying: Bool { applyingName != nil }

    /// The default remote's HEAD is out of scope; show the local branches and remote-only tips.
    var body: some View {
        SheetScaffold("Base branch", detents: .mediumLarge) {
            VStack(spacing: Space.md) {
                searchField
                if let applyError {
                    InlineBanner(.failure, title: applyError)
                        .padding(.horizontal, Space.lg)
                }
                content
                    .frame(maxHeight: .infinity)
            }
        }
        // One structured request per query: typing cancels the previous one (and its debounce), so
        // a slow response for an older query can't land after a newer one.
        .task(id: searchText) {
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await extras.loadBranchSuggestions(
                query: searchText.isEmpty ? nil : searchText, limit: 50)
            hasLoaded = true
        }
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Search branches", text: $searchText)
                .font(.paseo(.callout))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if extras.isLoadingBranchSuggestions {
                InlineProgress()
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(Palette.chip, in: .capsule)
        .padding(.horizontal, Space.lg)
    }

    @ViewBuilder private var content: some View {
        if !hasLoaded && suggestions.isEmpty {
            LoadingState()
        } else if suggestions.isEmpty {
            EmptyState(
                title: searchText.isEmpty ? "No branches" : "No matches",
                message: searchText.isEmpty
                    ? "The host returned no branches."
                    : "Nothing matches “\(searchText)”."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            apply(suggestion)
                        } label: {
                            HStack(spacing: Space.md) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.glyph(.small, weight: .medium))
                                    .foregroundStyle(Palette.secondaryInk)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                        .font(.paseo(.code))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    if suggestion.hasRemote == true && suggestion.hasLocal != true {
                                        Text("Remote only")
                                            .font(.paseo(.caption))
                                            .foregroundStyle(Palette.tertiaryInk)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if applyingName == suggestion.name {
                                    InlineProgress()
                                }
                            }
                            .padding(.horizontal, Space.xl)
                            .frame(minHeight: 46)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                        ClaudeDivider().padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func apply(_ suggestion: BranchSuggestion) {
        guard !isApplying else { return }
        applyingName = suggestion.name
        applyError = nil
        let remoteOnly = suggestion.hasLocal == false && suggestion.hasRemote == true
        let ref = (remoteOnly ? "refs/remotes/" : "refs/heads/") + suggestion.name
        Task {
            let applied = await session.workspaceDirectory.setBaseBranch(
                workspaceId, baseRef: ref)
            applyingName = nil
            if applied {
                Haptics.success()
                onApplied()
                dismiss()
            } else {
                Haptics.failure()
                applyError = session.workspaceDirectory.actionError
                    ?? "The host rejected the base branch."
            }
        }
    }
}
#endif
