#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One row of a directory listing, with its long-press menu. It takes plain values, so a pass
/// that only changes the page's name prompt or another row's busy state leaves it alone.
struct FileEntryRow: View {
    let entry: FileExplorerEntry
    /// Workspace-relative path: what a drag, "Add to chat" and "Copy relative path" carry.
    let relativePath: String
    let absolutePath: String
    let subtitle: String?
    /// The flash-highlighted row of "Reveal in Files page".
    let isRevealed: Bool
    /// A share or save-to-Files read is in flight for this row.
    let isBusy: Bool
    let onOpen: () -> Void
    let onShare: () -> Void
    let onSaveToFiles: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onNewFile: () -> Void
    let onNewFolder: () -> Void
    let onDelete: () -> Void

    @Environment(\.toast) private var toast
    /// "Mention in chat" from a row's long-press; nil disables the action.
    @Environment(\.mentionInChat) private var mentionInChat

    private var accessory: ListRow.Accessory {
        if isBusy { return .progress }
        return entry.isDirectory ? .chevron : .none
    }

    var body: some View {
        ListRow(
            title: entry.name,
            subtitle: subtitle,
            systemImage: entry.isDirectory ? "folder" : "doc",
            accessory: accessory,
            action: onOpen
        )
        .background(isRevealed ? Palette.chip.opacity(0.9) : Color.clear)
        .draggable(relativePath)
        .contextMenu {
            if !entry.isDirectory {
                Button("Add to chat", systemImage: "at") {
                    mentionInChat?(relativePath)
                }
            }
            Button("Share…", systemImage: "square.and.arrow.up", action: onShare)
            Button("Save to Files…", systemImage: "square.and.arrow.down", action: onSaveToFiles)
            Button("Rename…", systemImage: "pencil", action: onRename)
            Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
            if entry.isDirectory {
                Button("New file", systemImage: "doc", action: onNewFile)
                Button("New folder", systemImage: "folder", action: onNewFolder)
            }
            Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Copy path", systemImage: "doc.on.doc") {
                Clipboard.copy(absolutePath, toast: toast)
            }
            Button("Copy relative path", systemImage: "doc.on.doc") {
                Clipboard.copy(relativePath, toast: toast)
            }
        }
    }
}
#endif
