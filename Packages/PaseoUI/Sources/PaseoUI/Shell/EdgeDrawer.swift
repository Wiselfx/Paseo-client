#if canImport(UIKit)
import UIKit

/// The two drawers' shared geometry and material, read by `ShellContainerController`. The motion
/// lives there now: the surfaces are `UIView`s driven by one pan recognizer and one property
/// animator, so a drag never re-evaluates a SwiftUI body (UX-SPEC §1, §1.4).
enum EdgeDrawer {
    /// Touchable edge zone on each side.
    static let edgeZone: CGFloat = 24

    /// The display's corner radius, a constant: 55 on Face ID phones. Never interpolated with
    /// progress (§1.1) — a card that covers the screen has the screen's own shape.
    static let cornerRadius: CGFloat = 55

    /// The scrim over a covered surface is gone (E2 §1): the front card keeps its own colour and
    /// the depth comes from its shadow. Kept as the one place a scrim would be computed.
    static func scrimOpacity(_ progress: CGFloat, dark: Bool) -> Double {
        0
    }

    /// The front card's shadow: black at 10 % in light, 45 % in dark, a 24 pt blur along the
    /// leading edge (the panel mirrors it). Opacity follows the drawer progress, so it grows
    /// with the finger and the settle instead of popping in at the end.
    static let shadowRadius: CGFloat = 24
    static let shadowOpacityLight: Double = 0.10
    static let shadowOpacityDark: Double = 0.45
    static let leadingShadowOffset = CGSize(width: -2, height: 0)
    static let trailingShadowOffset = CGSize(width: 2, height: 0)

    static func shadowOpacity(_ progress: CGFloat, dark: Bool) -> Float {
        let amount = Double(min(max(progress, 0), 1))
        return Float(amount * (dark ? shadowOpacityDark : shadowOpacityLight))
    }
}
#endif
