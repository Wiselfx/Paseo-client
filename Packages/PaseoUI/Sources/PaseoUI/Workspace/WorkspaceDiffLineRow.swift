#if canImport(UIKit)
import SwiftUI

/// What a diff line asks its page to do: a tap (extends a range selection) or a review action
/// from its context menu.
enum DiffLineAction {
    case tap
    case comment
    case startSelection
    case extendSelection
    case clearSelection
}

/// One diff line: old/new line numbers, the sign and the monospaced text, tinted by kind.
///
/// Equatable on its inputs (the action closure is ignored) so SwiftUI skips unchanged rows when
/// the page's selection, sheet or hunk state changes.
struct WorkspaceDiffLineRow: View, Equatable {
    let row: DiffModel.Row
    let gutterWidth: CGFloat
    let totalWidth: CGFloat
    let wrap: Bool
    let isSelected: Bool
    let reviewEnabled: Bool
    /// A range selection is in progress, so the menu offers extend/clear instead of select.
    let selectionActive: Bool
    let onAction: (DiffLineAction) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.gutterWidth == rhs.gutterWidth && lhs.totalWidth == rhs.totalWidth
            && lhs.wrap == rhs.wrap && lhs.isSelected == rhs.isSelected
            && lhs.reviewEnabled == rhs.reviewEnabled && lhs.selectionActive == rhs.selectionActive
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.old.isEmpty ? " " : row.old)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: gutterWidth, alignment: .trailing)
            Text(row.new.isEmpty ? " " : row.new)
                .font(.paseo(.codeCaption))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: gutterWidth, alignment: .trailing)
                .padding(.trailing, 10)
            Text(row.sign)
                .font(.paseo(.code))
                .foregroundStyle(DiffRowStyle.signTint(row.kind))
                .frame(width: 13, alignment: .leading)
            Text(row.text.isEmpty ? " " : row.text)
                .font(.paseo(.code))
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: false)
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                .foregroundStyle(DiffRowStyle.contentTint(row.kind))
        }
        .frame(width: wrap ? nil : totalWidth, alignment: .leading)
        .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
        .padding(.vertical, 2)
        .background(isSelected ? Palette.warning.opacity(0.16) : DiffRowStyle.rowFill(row.kind))
        .contentShape(.rect)
        .onTapGesture { onAction(.tap) }
        .contextMenu {
            Button("Copy line", systemImage: "doc.on.doc") {
                Clipboard.copy(row.text)
            }
            if reviewEnabled, row.anchor != nil {
                Divider()
                Button("Add review comment…", systemImage: "text.bubble") {
                    onAction(.comment)
                }
                if selectionActive {
                    Button("Extend selection to this line", systemImage: "selection.pin.in.out") {
                        onAction(.extendSelection)
                    }
                    Button("Clear selection", systemImage: "xmark", role: .cancel) {
                        onAction(.clearSelection)
                    }
                } else {
                    Button("Select line range…", systemImage: "selection.pin.in.out") {
                        onAction(.startSelection)
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(reviewEnabled && row.anchor != nil ? .isButton : [])
    }

    private var accessibilityLabel: String {
        switch row.kind {
        case .add: "Added line \(row.new): \(row.text)"
        case .remove: "Removed line \(row.old): \(row.text)"
        case .context, .hunkHeader: "Line \(row.new): \(row.text)"
        }
    }
}
#endif
