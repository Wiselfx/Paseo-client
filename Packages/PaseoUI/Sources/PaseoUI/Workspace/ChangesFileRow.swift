#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One changed file: status letter, path (and old path), +/- stat. Opens the file's diff; the
/// context menu copies paths and offers discard.
struct ChangesFileRow: View {
    let file: ParsedDiffFile
    /// The checkout's working directory, for "Copy path".
    let cwd: String
    let canDiscard: Bool
    let onOpen: () -> Void
    let onDiscard: () -> Void

    @Environment(\.toast) private var toast

    var body: some View {
        let style = statusStyle
        Button(action: onOpen) {
            HStack(spacing: Space.md) {
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
                    if let oldPath = file.oldPath {
                        Text("from \(oldPath)")
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DiffStat(added: file.additions, removed: file.deletions)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.tertiaryInk)
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
                Clipboard.copy(URL(filePath: cwd).appending(path: file.path).path())
                toast?.show("Path copied")
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                Clipboard.copy(file.path)
                toast?.show("Relative path copied")
            }
            if canDiscard {
                Button("Discard changes…", systemImage: "trash", role: .destructive, action: onDiscard)
            }
        }
    }

    private var statusStyle: (letter: String, tint: Color, word: String) {
        if file.oldPath != nil { return ("R", Palette.unread, "Renamed") }
        if file.isNew { return ("A", Palette.diffAddedInk, "Added") }
        if file.isDeleted { return ("D", Palette.diffRemovedInk, "Deleted") }
        return ("M", Palette.warning, "Modified")
    }
}
#endif
