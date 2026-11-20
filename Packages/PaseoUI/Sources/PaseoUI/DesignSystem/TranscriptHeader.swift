#if canImport(UIKit)
import CoreGraphics

/// The conversation header's auto-hide (H2 §3). The reveal travel is a third of a real screen: the
/// user's "scroll up a lot".
enum TranscriptHeader {
    /// Travel toward newer content that hides the bar: a short flick, so it gets out of the way
    /// (upstream's own "scrolled away intentionally" distance is 24 px, `bottom-anchor-controller.ts`).
    static let hideDistance: CGFloat = 24
    /// Fraction of the keyboard-independent viewport you must pull toward older content to bring
    /// the bar back. A third of a screen, per the user's "a lot"; never a per-frame threshold.
    static let revealViewportFraction: CGFloat = 1.0 / 3.0

    /// The travel that reveals the bar at this viewport. Floored so a zero or tiny viewport (a
    /// preview, a pre-layout pass) still needs a deliberate pull.
    static func revealDistance(viewport: CGFloat) -> CGFloat {
        max(viewport * revealViewportFraction, Space.xl)
    }
}
#endif
