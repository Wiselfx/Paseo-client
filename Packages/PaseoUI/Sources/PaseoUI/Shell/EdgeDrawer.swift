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

    /// The scrim over a covered surface: 0.25 in light, 0.55 in dark, scaled by progress (§1.1).
    static func scrimOpacity(_ progress: CGFloat, dark: Bool) -> Double {
        Double(min(max(progress, 0), 1)) * (dark ? 0.55 : 0.25)
    }
}
#endif
