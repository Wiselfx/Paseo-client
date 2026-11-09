#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// The unified diff for one changed file: hunk headers, old/new line numbers, monospaced lines
/// on a two-axis scroll view (long lines are never wrapped), and added/removed rows tinted with
/// low-opacity adaptive fills.
struct WorkspaceChangesDiffView: View {
    let file: ParsedDiffFile
    let extras: WorkspaceGitExtras
    /// Commit diffs can't be discarded; hide the destructive affordance there.
    var allowsDiscard = true

    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false
    @State private var discardError: String?

    private let typography = ClaudeTypography()
    private let model: DiffModel

    init(file: ParsedDiffFile, extras: WorkspaceGitExtras, allowsDiscard: Bool = true) {
        self.file = file
        self.extras = extras
        self.allowsDiscard = allowsDiscard
        self.model = DiffModel(file: file)
    }

    var body: some View {
        VStack(spacing: 0) {
            pathHeader
            ClaudeDivider()
            if let discardError {
                Text(discardError)
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
        }
        .background(ClaudePalette.panel)
        .foregroundStyle(ClaudePalette.ink)
        .navigationTitle((file.path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsDiscard, extras.capabilities.supportsDiscardChanges {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(ClaudePalette.failureInk)
                    }
                    .accessibilityLabel("Discard changes to this file")
                    .disabled(extras.isDiscarding)
                }
            }
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { performDiscard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all changes in \(file.path). This cannot be undone.")
        }
    }

    // MARK: Path header

    private var pathHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(file.path)
                    .font(typography.mono(11.5))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                if let oldPath = file.oldPath {
                    Text("renamed from \(oldPath)")
                        .font(typography.mono(10.5))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("+\(file.additions)")
                    .foregroundStyle(ClaudePalette.successInk)
                Text("−\(file.deletions)")
                    .foregroundStyle(ClaudePalette.failureInk)
            }
            .font(typography.mono(12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch file.status {
        case .binary:
            centeredMessage(
                symbol: "archivebox",
                title: "Binary file",
                subtitle: "Binary files can't be shown as a diff.")
        case .tooLarge:
            centeredMessage(
                symbol: "doc.text",
                title: "File too large",
                subtitle: "The diff for this file was omitted by the daemon.")
        default:
            if model.rows.isEmpty {
                centeredMessage(
                    symbol: "checkmark.circle",
                    title: "No textual changes",
                    subtitle: "There's nothing to show for this file.")
            } else {
                diffScroll
            }
        }
    }

    private func centeredMessage(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(title)
                .font(typography.sans(16, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text(subtitle)
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var diffScroll: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.rows) { row in
                    lineRow(row)
                }
            }
            .padding(.vertical, 8)
            .textSelection(.enabled)
        }
        .background(ClaudePalette.codeBackground)
    }

    private func lineRow(_ row: DiffModel.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.old)
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 6)
            Text(row.new)
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(width: 38, alignment: .trailing)
                .padding(.trailing, 10)
            Text(row.sign)
                .foregroundStyle(signTint(row.kind))
                .frame(width: 13, alignment: .leading)
            Text(row.text.isEmpty ? " " : row.text)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(contentTint(row.kind))
        }
        .font(typography.mono(12.5))
        .frame(width: model.totalWidth, alignment: .leading)
        .padding(.vertical, 2)
        .background(rowFill(row.kind))
    }

    private func contentTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .hunkHeader: ClaudePalette.tertiaryInk
        case .context, .add, .remove: ClaudePalette.primaryInk
        }
    }

    private func signTint(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: ClaudePalette.successInk
        case .remove: ClaudePalette.failureInk
        case .context, .hunkHeader: .clear
        }
    }

    private func rowFill(_ kind: DiffModel.RowKind) -> Color {
        switch kind {
        case .add: Self.addedTint
        case .remove: Self.removedTint
        case .hunkHeader: ClaudePalette.chip
        case .context: .clear
        }
    }

    /// Low-opacity green/red that stays readable on dark and light canvases.
    private static let addedTint = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.29, green: 0.82, blue: 0.44, alpha: 0.18)
                : UIColor(red: 0.16, green: 0.62, blue: 0.35, alpha: 0.14)
        })
    private static let removedTint = Color(
        uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(red: 0.93, green: 0.42, blue: 0.37, alpha: 0.20)
                : UIColor(red: 0.80, green: 0.22, blue: 0.17, alpha: 0.13)
        })

    private func performDiscard() {
        Task {
            let discarded = await extras.discard(paths: [file.path])
            if discarded {
                Haptics.success()
                dismiss()
            } else {
                Haptics.failure()
                discardError = extras.actionError ?? "The discard failed."
            }
        }
    }
}

// MARK: - Diff line model

/// Flattens a file's hunks into renderable rows with old/new line numbers, and measures the
/// content width so every row can fill the horizontal scroll range.
private struct DiffModel {
    enum RowKind {
        case hunkHeader
        case context
        case add
        case remove
    }

    struct Row: Identifiable {
        let id: Int
        let old: String
        let new: String
        let sign: String
        let kind: RowKind
        let text: String
    }

    let rows: [Row]
    let totalWidth: CGFloat

    init(file: ParsedDiffFile) {
        var rows: [Row] = []
        var nextId = 0
        for hunk in file.hunks {
            var oldLine = hunk.oldStart
            var newLine = hunk.newStart
            let hasHeaderLine = hunk.lines.contains { $0.type == .header }
            if !hasHeaderLine {
                rows.append(
                    Row(
                        id: nextId, old: "", new: "", sign: "", kind: .hunkHeader,
                        text: "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"))
                nextId += 1
            }
            for line in hunk.lines {
                switch line.type {
                case .header:
                    rows.append(
                        Row(
                            id: nextId, old: "", new: "", sign: "", kind: .hunkHeader,
                            text: line.content))
                    nextId += 1
                case .context, .unknown:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "\(newLine)", sign: " ",
                            kind: .context, text: line.content))
                    nextId += 1
                    oldLine += 1
                    newLine += 1
                case .add:
                    rows.append(
                        Row(
                            id: nextId, old: "", new: "\(newLine)", sign: "+",
                            kind: .add, text: line.content))
                    nextId += 1
                    newLine += 1
                case .remove:
                    rows.append(
                        Row(
                            id: nextId, old: "\(oldLine)", new: "", sign: "-",
                            kind: .remove, text: line.content))
                    nextId += 1
                    oldLine += 1
                }
            }
        }
        self.rows = rows

        let font =
            UIFont(name: ClaudeTypography.anthropicMono, size: 12.5)
            ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let unit = ("M" as NSString).size(withAttributes: [.font: font]).width
        let gutters: CGFloat = 38 + 6 + 38 + 10 + 13 + 12 + 16
        let longest = rows.map { $0.text.count }.max() ?? 0
        self.totalWidth = max(280, gutters + unit * CGFloat(longest))
    }
}
#endif
