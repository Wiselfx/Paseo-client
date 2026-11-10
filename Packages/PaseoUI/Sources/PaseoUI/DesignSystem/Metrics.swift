#if canImport(UIKit)
import CoreGraphics

/// Corner radii, one set for the whole app. Capsules and circles stay capsules and circles.
/// Values follow OCU's official scale (`06:1010,1016`): controls 8, cards and code 12, bubbles 18,
/// composer 14.
enum Radius {
    /// Inline code, tiny marks.
    static let xs: CGFloat = 4
    /// Chips' inner marks, small tiles.
    static let sm: CGFloat = 8
    /// Cards, code blocks, tool cards, banners.
    static let md: CGFloat = 12
    /// Large cards, the permission card (OCU card).
    static let lg: CGFloat = 12
    /// The user bubble.
    static let bubble: CGFloat = 18
    /// Grouped row blocks (`RowGroup`) and Markdown code blocks (OCU card/code).
    static let group: CGFloat = 12
    /// The open composer card (OCU composer).
    static let composer: CGFloat = 14
    /// The composer at rest: a one-line pill.
    static let composerPill: CGFloat = 24
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
