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
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.failureInk)
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
        .background(Palette.panel)
        .foregroundStyle(Palette.ink)
        .navigationTitle(commit.shortSha)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openFile) { file in
            WorkspaceChangesDiffView(file: file, extras: extras, allowsDiscard: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject)
                .font(.paseo(.callout, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(commit.shortSha)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                Text("· \(commit.authorName)")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(relativeAge)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.tertiaryInk)
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
                    .font(.paseo(.codeCaption, weight: .semibold))
                    .foregroundStyle(style.tint)
                    .frame(width: 22, height: 22)
                    .background(style.tint.opacity(0.16), in: .rect(cornerRadius: Radius.sm))
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.paseo(.codeSmall))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(PaseoFormat.integer(file.additions))")
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.successInk)
                Text("−\(PaseoFormat.integer(file.deletions))")
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.failureInk)
                if loadingPath == file.path {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
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
        case .added: return ("A", Palette.successInk, "Added")
        case .deleted: return ("D", Palette.failureInk, "Deleted")
        case .renamed: return ("R", Palette.unread, "Renamed")
        case .modified, .unknown, .none: return ("M", Palette.warning, "Modified")
        }
    }
}
#endif
