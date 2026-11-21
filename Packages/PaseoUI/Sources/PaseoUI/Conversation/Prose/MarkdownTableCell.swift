#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One table cell: the inline content, the header wash and the row divider. A tappable header
/// cell is a real `Button`, so it gets button behavior (highlight, Switch Control and keyboard
/// activation) and does not fight the cell text's selection; body cells carry no gesture at all.
struct MarkdownTableCell: View {
    let cell: [MarkdownInline]
    let isHeader: Bool
    let alignment: MarkdownColumnAlignment
    let rowIndex: Int
    let rowsCount: Int
    let theme: ClaudeMarkdownTheme
    /// Opens the table full screen; non-nil only for a header cell that can do that.
    var onExpand: (() -> Void)? = nil

    var body: some View {
        let content = MarkdownInlineText(
            content: cell, theme: theme,
            font: isHeader ? theme.face(for: theme.bodyFont, strong: true, emphasis: false) : theme.bodyFont,
            alignment: alignment
        )
        .padding(.horizontal, Space.md).padding(.vertical, MarkdownMetrics.tableCellVerticalInset)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(isHeader ? theme.tableHeaderBackground : .clear)
        .overlay(alignment: .bottom) {
            if rowIndex < rowsCount { Rectangle().fill(theme.rule).frame(height: 0.5) }
        }
        if let onExpand {
            Button(action: onExpand) {
                content.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens table full screen")
        } else {
            content
        }
    }
}
#endif
