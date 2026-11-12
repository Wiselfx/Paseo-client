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
    /// The OG image slot (G9 C6): unfurl heroes crop to 1.91:1, reserved from frame one.
    static let ogHeroAspect: CGFloat = 1.91
    /// The link row's icon box (G9 C6): 32 pt glyph well in the 56 pt row.
    static let linkIconSize: CGFloat = 32
    /// The overlay pill's vertical inset (G11 C3): the duration pill floats 3 pt in.
    static let overlayVPadding: CGFloat = 3
    /// The audio waveform's bar count (G11 C4): fixed, so the draw is O(1) per paint.
    static let audioBarCount = 48
}

/// The sidebar's rows.
enum SidebarMetrics {
    /// The usage footer's line height, for the meter rows **and** the status line they replace.
    /// Both are single `.caption` rows with the same `minHeight`, so the footer cannot change
    /// height when the first load lands and the page above it cannot jump (H4 §2).
    static let usageLineHeight: CGFloat = 20
}

/// The conversation header's auto-hide (H2 §3) and the wash that keeps a bubble from reading
/// through the title. The reveal travel is a third of a real screen: the user's "scroll up a lot".
enum TranscriptHeader {
    /// Travel toward newer content that hides the bar: a short flick, so it gets out of the way
    /// (upstream's own "scrolled away intentionally" distance is 24 px, `bottom-anchor-controller.ts`).
    static let hideDistance: CGFloat = 24
    /// Fraction of the keyboard-independent viewport you must pull toward older content to bring
    /// the bar back. A third of a screen, per the user's "a lot"; never a per-frame threshold.
    static let revealViewportFraction: CGFloat = 1.0 / 3.0
    /// The wash behind the visible bar: opaque enough that prose cannot read through the
    /// subtitle, in light and dark.
    static let backdropOpacity: Double = 0.94
    /// Where the wash starts fading out, as a fraction of the bar's height. The fade keeps a row
    /// edge from meeting a hard line while the header is up.
    static let backdropFadeLocation: CGFloat = 0.72

    /// The travel that reveals the bar at this viewport. Floored so a zero or tiny viewport (a
    /// preview, a pre-layout pass) still needs a deliberate pull.
    static func revealDistance(viewport: CGFloat) -> CGFloat {
        max(viewport * revealViewportFraction, Space.xl)
    }
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

    // MARK: The context meter (H3 §1)

    /// The ring inside the meter's 36 pt slot. 24 pt leaves room for the number inside it at the
    /// default type size, and 1.5 pt keeps it a ring rather than a spinner (D2 §1).
    static let meterRingSize: CGFloat = 24
    static let meterRingLineWidth: CGFloat = 1.5

    // MARK: The corner expand control (H3 §2)

    /// The visual circle in the card's top-trailing corner. 28 pt, not the row's 36: it is a
    /// convenience, not an action, and every point it takes comes out of the text column while it
    /// is shown. A 44 pt hit frame with a 28 pt circle keeps the circle
    /// `(hitSize − expandSize) / 2 = 8` pt from the card's edges, the same 8 pt the row's circles
    /// keep (E1 §4).
    static let expandSize: CGFloat = 28
    /// The expand control appears at this many **laid-out** draft lines
    /// (`ComposerUITextView.visualLineCount`: the field's own text layout, so Dynamic Type, a wider
    /// window and proportional glyphs all count correctly; 5 is the threshold M8b used) …
    static let expandShowLines = 5
    /// … and only leaves below this one. One line of dead band: the control's own reserve narrows
    /// the text column, and a re-wrap at the threshold must not make it flicker. A narrower column
    /// can only add lines (so appearing cannot fall to this threshold) and a wider one can only
    /// remove them (so disappearing cannot climb back above `expandShowLines`) (H3 §2).
    static let expandHideLines = expandShowLines - 1
}
#endif
