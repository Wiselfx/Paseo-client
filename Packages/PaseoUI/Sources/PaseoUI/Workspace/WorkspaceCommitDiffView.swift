#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// One commit ahead of base: the commit header (subject, short sha, author, relative age),
/// then its changed files. Tapping a file loads its diff inside the commit and opens the
/// shared unified diff view without the discard affordance.
struct WorkspaceCommitDiffView: View {
    let commit: CheckoutCommit
    let actions: WorkspaceGitActions
    let extras: WorkspaceGitExtras

    @State private var openFile: ParsedDiffFile?
    @State private var loadingPath: String?
    @State private var loadError: String?

    private let typography = ClaudeTypography()

    private var relativeAge: String {
        guard let date = PaseoDate.parse(commit.authorDate) else { return commit.authorDate }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ClaudeDivider()
            if let loadError {
                Text(loadError)
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(commit.files) { file in
                        fileRow(file)
                        if file.id != commit.files.last?.id {
                            ClaudeDivider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(ClaudePalette.panel)
        .foregroundStyle(ClaudePalette.ink)
        .navigationTitle(commit.shortSha)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openFile) { file in
            WorkspaceChangesDiffView(file: file, extras: extras, allowsDiscard: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject)
                .font(typography.sans(15, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(commit.shortSha)
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Text("· \(commit.authorName)")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(relativeAge)
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fileRow(_ file: CheckoutCommitFile) -> some View {
        let style = style(for: file.status)
        return Button {
            Haptics.selection()
            Task { await openDiff(for: file) }
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(file.additions)")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(file.deletions)")
                    .font(typography.mono(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                if loadingPath == file.path {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loadingPath != nil)
        .accessibilityLabel("\(style.word) \(file.path)")
    }

    private func openDiff(for file: CheckoutCommitFile) async {
        guard loadingPath == nil else { return }
        loadingPath = file.path
        loadError = nil
        let parsed = await actions.loadCommitFileDiff(sha: commit.sha, path: file.path)
        loadingPath = nil
        if let parsed {
            openFile = parsed
        } else if actions.commitFileDiffError != nil {
            loadError = actions.commitFileDiffError
        } else {
            // Absent or binary file inside this commit: nothing textual to show.
            loadError = "No textual diff for \(file.path) in this commit."
        }
    }

    private func style(for status: CheckoutCommitFileStatus?) -> (letter: String, tint: Color, word: String) {
        switch status {
        case .added: return ("A", ClaudePalette.successInk, "Added")
        case .deleted: return ("D", ClaudePalette.failureInk, "Deleted")
        case .renamed: return ("R", ClaudePalette.unread, "Renamed")
        case .modified, .unknown, .none: return ("M", ClaudePalette.warning, "Modified")
        }
    }
}
#endif
