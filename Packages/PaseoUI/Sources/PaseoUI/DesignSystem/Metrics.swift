#if canImport(UIKit)
import CoreGraphics

/// Corner radii, one set for the whole app. Capsules and circles stay capsules and circles.
enum Radius {
    /// Inline code, tiny marks.
    static let xs: CGFloat = 4
    /// Chips' inner marks, small tiles.
    static let sm: CGFloat = 8
    /// Cards, code blocks, tool cards, banners.
    static let md: CGFloat = 12
    /// Large cards, the permission card.
    static let lg: CGFloat = 16
    /// The user bubble.
    static let bubble: CGFloat = 20
    /// Grouped row blocks (`RowGroup`), the composer card.
    static let group: CGFloat = 28
}

/// Spacing steps. Screen tickets replace spacing literals with these.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}
#endif
