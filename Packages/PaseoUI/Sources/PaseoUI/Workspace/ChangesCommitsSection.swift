#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// "Commits ahead of <base>" rows, behind the `commitsList` gate. Tapping a row opens the
/// commit's files; each file opens the shared diff view without the discard affordance.
struct ChangesCommitsSection: View {
    let gitActions: WorkspaceGitActions
    let baseRef: String?
    let onOpen: (CheckoutCommit) -> Void

    var body: some View {
        if !gitActions.commits.isEmpty || gitActions.commitsError != nil {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Commits ahead of \(baseRef ?? "base")")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: 8)
                    if !gitActions.commits.isEmpty {
                        Text("\(PaseoFormat.integer(gitActions.commits.count))")
                            .font(.paseo(.codeSmall))
                            .foregroundStyle(Palette.tertiaryInk)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.sm)
                if let message = gitActions.commitsError {
                    Text(message)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .padding(.horizontal, Space.xl)
                        .padding(.bottom, Space.sm)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(gitActions.commits) { commit in
                            VStack(spacing: 0) {
                                ChangesCommitRow(commit: commit) { onOpen(commit) }
                                ClaudeDivider()
                                    .padding(.leading, Space.xl)
                                    .opacity(commit.id == gitActions.commits.last?.id ? 0 : 1)
                            }
                        }
                    }
                    .padding(.bottom, Space.md)
                }
            }
        }
    }
}
#endif
