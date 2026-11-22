#if canImport(UIKit)
import SwiftUI

/// A hunk's pinned "@@ … @@" header; tapping it collapses or expands the hunk.
struct DiffHunkHeader: View {
    let text: String
    let hunk: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: 14)
                Text(text)
                    .foregroundStyle(DiffRowStyle.contentTint(.hunkHeader))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.paseo(.codeSmall))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(DiffRowStyle.rowFill(.hunkHeader))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hunk \(hunk + 1), \(isCollapsed ? "collapsed" : "expanded")")
    }
}
#endif
