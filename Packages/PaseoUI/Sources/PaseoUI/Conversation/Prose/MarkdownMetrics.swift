#if canImport(UIKit)
import SwiftUI

/// Prose spacing that is not on the shared `Space` scale. The values follow the measured
/// Markdown layout (the blockquote's ".6em 1em", the list marker gap, the table cell inset),
/// so they are named here once instead of repeating as literals through the block views.
enum MarkdownMetrics {
    /// A blockquote's horizontal inset: 1em.
    static let quoteHorizontalInset: CGFloat = 14
    /// A blockquote's vertical inset: .6em.
    static let quoteVerticalInset: CGFloat = 8.4
    /// The gap between a list marker and its item's blocks.
    static let listMarkerSpacing: CGFloat = 10
    /// The narrowest a list marker column gets, so "•" and "10." line up on the trailing edge.
    static let listMarkerMinWidth: CGFloat = 18
    /// A table cell's vertical inset (the horizontal one is `Space.md`).
    static let tableCellVerticalInset: CGFloat = 10
}
#endif
