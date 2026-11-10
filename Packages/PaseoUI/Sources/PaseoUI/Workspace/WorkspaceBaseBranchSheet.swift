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
    @State private var isApplying = false
    @State private var applyError: String?
    @State private var hasLoaded = false

    private let typography = ClaudeTypography()

    private var suggestions: [BranchSuggestion] { extras.branchSuggestions }

    /// The default remote's HEAD is out of scope; show the local branches and remote-only tips.
    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Base branch", close: { dismiss() })
            searchField
            if let applyError {
                Text(applyError)
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            content
                .frame(maxHeight: .infinity)
            Spacer(minLength: 8)
        }
        .background(ClaudePalette.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .task {
            await extras.loadBranchSuggestions(limit: 50)
            hasLoaded = true
        }
        .onChange(of: searchText) { _, value in
            Task { await extras.loadBranchSuggestions(query: value.isEmpty ? nil : value, limit: 50) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
            TextField("Search branches", text: $searchText)
                .font(typography.sans(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if extras.isLoadingBranchSuggestions {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(ClaudePalette.chip, in: .capsule)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var content: some View {
        if !hasLoaded && suggestions.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suggestions.isEmpty {
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No branches" : "No matches")
                    .font(typography.sans(15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(searchText.isEmpty
                    ? "The daemon returned no branches."
                    : "Nothing matches “\(searchText)”.")
                    .font(typography.sans(13))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            apply(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ClaudePalette.secondaryInk)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name)
                                        .font(typography.mono(13))
                                        .foregroundStyle(ClaudePalette.ink)
                                        .lineLimit(1)
                                    if suggestion.hasRemote == true && suggestion.hasLocal != true {
                                        Text("Remote only")
                                            .font(typography.sans(11))
                                            .foregroundStyle(ClaudePalette.tertiaryInk)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if isApplying {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 46)
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
        isApplying = true
        applyError = nil
        Haptics.selection()
        let remoteOnly = suggestion.hasLocal == false && suggestion.hasRemote == true
        let ref = (remoteOnly ? "refs/remotes/" : "refs/heads/") + suggestion.name
        Task {
            let applied = await session.workspaceDirectory.setBaseBranch(
                workspaceId, baseRef: ref)
            isApplying = false
            if applied {
                Haptics.success()
                onApplied()
                dismiss()
            } else {
                Haptics.failure()
                applyError = session.workspaceDirectory.actionError
                    ?? "The daemon rejected the base branch."
            }
        }
    }
}
#endif
