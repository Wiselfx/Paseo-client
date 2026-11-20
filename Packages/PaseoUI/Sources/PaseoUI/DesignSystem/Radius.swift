#if canImport(UIKit)
import CoreGraphics

/// Corner radii, one set for the whole app. Capsules and circles stay capsules and circles.
/// Values follow OCU's official scale (`06:1010,1016`): controls 8, cards and code 12, bubbles 18,
/// composer 24 (E1 §4).
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
    /// The open composer card: Claude's card measures ≈24 (E1 §4). The at-rest pill is the same
    /// radius at 48 pt tall, so growing it changes height and silhouette, never the corner.
    static let composer: CGFloat = 24
    /// The composer at rest: a one-line pill.
    static let composerPill: CGFloat = 24
}
#endif
