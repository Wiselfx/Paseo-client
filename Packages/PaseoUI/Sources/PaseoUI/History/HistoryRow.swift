#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One History row: the agent's title and subtitle, its age or archived badge, the context menu
/// (Open, Rename…, Copy agent id, then the destructive verb) and the trailing swipe action.
struct HistoryRow: View {
    let row: HistoryModel.Row
    /// True while an archived agent is being unarchived for opening; the badge becomes progress.
    let isUnarchiving: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onCopyID: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ListRow(title: row.title, subtitle: row.subtitle, action: onOpen)
            trailing
        }
        .panelRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.archived ? "Archived agent, \(row.title)" : row.title)
        // The subtitle and age are on screen for every row, so VoiceOver hears them too.
        .accessibilityValue([row.subtitle, row.date.map(PaseoFormat.relative)].compactMap { $0 }.formatted())
        .contextMenu { menu }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.archived {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(role: .destructive, action: onArchive) {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if isUnarchiving {
            InlineProgress()
                .padding(.trailing, Space.lg)
        } else {
            VStack(alignment: .trailing, spacing: Space.xs) {
                if row.archived {
                    Text("Archived")
                        .font(.paseo(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 2)
                        .background(Palette.chip, in: .capsule)
                }
                // `2m ago`, `yesterday`: `PaseoFormat` owns the wording (UX-SPEC §0.2).
                Text(row.date.map(PaseoFormat.relative) ?? "")
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.captionInk)
            }
            .padding(.trailing, Space.lg)
        }
    }

    @ViewBuilder private var menu: some View {
        Button(action: onOpen) {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        Button(action: onRename) {
            Label("Rename…", systemImage: "pencil")
        }
        Button(action: onCopyID) {
            Label("Copy agent ID", systemImage: "doc.on.doc")
        }
        Divider()
        if row.archived {
            Button(role: .destructive, action: onDelete) {
                Label("Delete permanently", systemImage: "trash")
            }
        } else {
            Button(role: .destructive, action: onArchive) {
                Label("Archive agent", systemImage: "archivebox")
            }
        }
    }
}
#endif
