#if canImport(UIKit)
import SwiftUI
import UIKit

/// How a key of `PaseoTerminalKeyBar` looks: a translucent rounded key with a hairline edge on the
/// keyboard's own material, brighter while pressed, tinted while latched. Plain translucent fills
/// (no blur per key) keep a press down to a few layer properties. With Reduce Transparency on, the
/// fills are opaque.
enum TerminalKeyStyle {
    /// A key's corner: continuous, like the system keyboard's keys.
    static let cornerRadius = Radius.md
    /// The narrowest a key gets; its height is `TerminalChrome.hit`.
    static let minWidth: CGFloat = 40
    /// The gap between neighbouring keys, and the wider gap between groups.
    static let keyGap = Space.xs
    static let groupGap = Space.md
    /// The key's edge.
    static let hairline: CGFloat = 0.5
    /// A pressed key shrinks to this, and settles back over `releaseDuration`.
    static let pressedScale: CGFloat = 0.94
    static let releaseDuration: TimeInterval = 0.12
    /// A latched key's tint over the bar.
    private static let latchedFill: CGFloat = 0.30
    private static let latchedPressedFill: CGFloat = 0.42

    /// The key's fill for its current state. Resolved per trait collection by UIKit, so a
    /// colour-scheme change needs no work here.
    static func fill(pressed: Bool, latched: Bool) -> UIColor {
        if latched {
            return UIColor(Palette.accent).withAlphaComponent(pressed ? latchedPressedFill : latchedFill)
        }
        let opaque = UIAccessibility.isReduceTransparencyEnabled
        return UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch (opaque, dark, pressed) {
            case (false, false, false): return UIColor(white: 1, alpha: 0.62)
            case (false, false, true): return UIColor(white: 1, alpha: 1)
            case (false, true, false): return UIColor(white: 1, alpha: 0.16)
            case (false, true, true): return UIColor(white: 1, alpha: 0.34)
            case (true, false, false): return UIColor(white: 1, alpha: 1)
            case (true, false, true): return UIColor(white: 0.86, alpha: 1)
            case (true, true, false): return UIColor(white: 0.22, alpha: 1)
            case (true, true, true): return UIColor(white: 0.36, alpha: 1)
            }
        }
    }

    /// The hairline around a key, resolved for `traits` (a layer border takes a `CGColor`).
    static func edge(latched: Bool, traits: UITraitCollection) -> CGColor {
        if latched { return UIColor(Palette.accent).resolvedColor(with: traits).cgColor }
        let dark = traits.userInterfaceStyle == .dark
        let color = dark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.10)
        return color.cgColor
    }

    static func glyph(latched: Bool) -> UIColor {
        latched ? UIColor(Palette.accentInk) : UIColor(Palette.ink)
    }
}
#endif
