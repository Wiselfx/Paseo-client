#if canImport(UIKit)
import CoreGraphics

/// Touch targets and other numbers more than one surface draws, so nothing has to re-invent
/// Apple's 44 pt minimum (H5's image card actions, the prose viewers).
enum Metrics {
    /// The minimum touch target: every icon-only control reaches it.
    static let hitSize: CGFloat = 44
    /// The card press depth (G1 §1.2): content settles to 98 % while held.
    static let cardPressScale: CGFloat = 0.98
    /// The row card's floor (G1 §1.1): 56 pt including the card's own padding.
    static let rowCardMinHeight: CGFloat = 56
    /// The animated-badge capsule insets (G3 §4.6: the GIF bugle on a photo).
    static let badgeHPadding: CGFloat = 6
    static let badgeVPadding: CGFloat = 2
    /// The viewer chrome's per-button width (G3 §4.6): icon plus 44 pt hit area.
    static let viewerChromeButtonWidth: CGFloat = 48
    /// The drag-down dismiss threshold (G3 §4.6, R-3): travel past 120 pt, or a 800 pt/s
    /// flick, dismisses; anything less springs home.
    static let dismissDistance: CGFloat = 120
    static let dismissVelocity: CGFloat = 800
    /// The dismiss/spring-home animator caps (G3 §4.6): the `UISpringTimingParameters`
    /// (dampingRatio 1, velocity-matched) drive the curve; these bound its length.
    static let dismissDuration: Double = 0.25
    static let springHomeDuration: Double = 0.32
    /// The card header capsule insets (G4 C9): 10 pt horizontal, 6 pt vertical.
    static let cardHeaderHPadding: CGFloat = 10
    static let cardHeaderVPadding: CGFloat = 6
    /// The source preview's scroll cap (G4/G5): code boxes never push the turn away.
    static let sourcePreviewMaxHeight: CGFloat = 260
    /// Compact placeholder height before layout (G4 C9): small, for one frame only.
    static let placeholderCompactHeight: CGFloat = 120
    /// The offscreen snapshot clamp (G4 §4.1): snapshots never exceed ~4 MP.
    static let offscreenSnapshotMaxWidth: CGFloat = 1365
    /// The audio waveform's tallest bar (G11 C4), in the row and the dictation overlay.
    static let audioWaveformHeight: CGFloat = 28
    /// Gallery tile gutters (G7 C2): 2 pt hairlines between tiles.
    static let galleryTileSpacing: CGFloat = 2
    /// The mermaid render timeout (G4 §4.1): WebKit answers in ms; 20 s is failure.
    static let mermaidRenderTimeout: Double = 20
    /// The inline code icon buttons (G5 C8 Preview): 28 pt glyph in a 44 pt hit area.
    static let codeIconSize: CGFloat = 28
    /// The per-turn chart boxes (G13 C16): fixed from the first frame whether or not
    /// any turn has been observed, so the sheet never jumps when data arrives.
    static let turnChartHeight: CGFloat = 120
    /// The cost-by-model bar thickness (G13 C16): a hairline under each row's figures.
    static let costBarThickness: CGFloat = 4
    /// The OG image slot (G9 C6): unfurl heroes crop to 1.91:1, reserved from frame one.
    static let ogHeroAspect: CGFloat = 1.91
    /// The link row's icon box (G9 C6): 32 pt glyph well in the 56 pt row.
    static let linkIconSize: CGFloat = 32
    /// The overlay pill's vertical inset (G11 C3): the duration pill floats 3 pt in.
    static let overlayVPadding: CGFloat = 3
    /// The audio waveform's bar count (G11 C4): fixed, so the draw is O(1) per paint.
    static let audioBarCount = 48
    /// The table overflow fade (C1 §9.1): the trailing strip that hints scrollability
    /// and opens the full screen. Narrow enough to never cover a cell's content.
    static let tableFadeWidth: CGFloat = 24
    /// A sent image's height cap in the user bubble (C5 §9.5): full-bleed width,
    /// aspect-fit, never taller than this.
    static let userImageMaxHeight: CGFloat = 220
}
#endif
