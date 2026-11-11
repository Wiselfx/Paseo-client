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

/// Touch targets and other numbers more than one surface draws, so nothing has to re-invent
/// Apple's 44 pt minimum (H5's image card actions, the prose viewers).
enum Metrics {
    /// The minimum touch target: every icon-only control reaches it.
    static let hitSize: CGFloat = 44
}

/// The composer's shape, measured from Claude's composer (screenshots at 3×, E1 §4).
///
/// Every number the card and its rows draw comes from here, so the draft and the conversation
/// cannot drift apart. The circles are 36 pt inside 44 pt hit areas; the row's frames hang
/// `controlOverhang` into the card's padding so the circles sit 8 pt from the card's edge.
enum ComposerMetrics {
    /// The card's margin to the screen edge.
    static let sideInset: CGFloat = 8
    /// The card's top and bottom padding when open.
    static let verticalInset: CGFloat = 8
    /// The draft's one-line pill (a capsule at this height).
    static let pillHeight: CGFloat = 48
    /// The hairline around the card's fill.
    static let hairline: CGFloat = 0.7
    /// The card's shadow in light: black at 6 %, 12 pt blur, 2 pt down.
    static let shadowRadius: CGFloat = 12
    static let shadowY: CGFloat = 2
    /// The field's own inset inside the card's padding: 8 + 6 = 14 pt from the card's edge to
    /// the first glyph (the measured 13–14).
    static let textInsetLeading: CGFloat = 6
    /// 8 + 7 = 15 pt from the card's top to the line box.
    static let textInsetTop: CGFloat = 7
    static let textInsetBottom: CGFloat = 1
    /// Field → controls row: 12 pt of air, one of which is the field's own bottom inset.
    static let fieldRowGap: CGFloat = 11
    /// The visual size of every control in the row.
    static let controlSize: CGFloat = 36
    /// The touch target around it.
    static let hitSize: CGFloat = 44
    /// The row's 44 pt frames hang this far into the card's padding.
    static let controlOverhang: CGFloat = (hitSize - controlSize) / 2
    /// Between the controls in a row.
    static let controlSpacing: CGFloat = 8
    /// The model and fast-mode chips' horizontal padding.
    static let chipPadding: CGFloat = 14
    /// The waveform's tallest bar, in the dictation overlay and the voice bar.
    static let waveformHeight: CGFloat = 28
    static let waveformBarWidth: CGFloat = 3
    static let waveformBarGap: CGFloat = 2
}
#endif
