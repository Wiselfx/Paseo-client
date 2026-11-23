#if canImport(UIKit)
import SwiftUI
import UIKit

/// How a key of `PaseoTerminalKeyBar` looks: a translucent rounded key with a hairline edge on the
/// keyboard's own material, brighter while pressed, tinted while latched. Plain translucent fills
/// (no blur per key) keep a press down to a few layer properties. With Reduce Transparency on, the
/// fills are opaque.
///
/// Every colour is built once: a press swaps one cached `UIColor` for another (UIKit resolves it
/// for the current appearance), so pressing a key allocates nothing.
@MainActor
enum TerminalKeyStyle {
    /// A key's corner: continuous, like the system keyboard's keys.
    static let cornerRadius = Radius.md
    /// The narrowest a key draws; its height is `TerminalChrome.hit`. Narrower than 44 so Esc, Tab,
    /// Ctrl and all four arrows fit on the narrowest phone without scrolling; the touch target
    /// still reaches 44 pt because each key takes half the gap on either side (`hitOutset`).
    static let minWidth: CGFloat = 40
    /// The gap between neighbouring keys, and the wider gap between groups.
    static let keyGap = Space.xs
    static let groupGap = Space.md
    /// How far a key's touch area reaches past its drawn edge, sideways: half the gap, so
    /// neighbouring targets meet without overlapping.
    static let hitOutset = keyGap / 2
    /// The key's edge.
    static let hairline = TerminalChrome.hairline
    /// A pressed key shrinks to this, and settles back over `releaseDuration`.
    static let pressedScale: CGFloat = 0.94
    static let releaseDuration: TimeInterval = 0.12
    /// Holding an arrow: the wait before it repeats, then the beat it repeats at (the hardware
    /// keyboard's feel).
    static let repeatDelay: Duration = .milliseconds(350)
    static let repeatInterval: Duration = .milliseconds(60)
    /// The largest text size the keys follow: like the system keyboard, the bar stops growing its
    /// glyphs where they would overflow a 44 pt key.
    static let maximumContentSize: UIContentSizeCategory = .accessibilityMedium

    private static let latchedFill = UIColor(Palette.accent).withAlphaComponent(0.30)
    private static let latchedPressedFill = UIColor(Palette.accent).withAlphaComponent(0.42)
    private static let restFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 1, alpha: 0.62)
    }
    private static let pressedFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.34) : UIColor(white: 1, alpha: 1)
    }
    private static let opaqueRestFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 1, alpha: 1)
    }
    private static let opaquePressedFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.36, alpha: 1) : UIColor(white: 0.86, alpha: 1)
    }
    private static let darkEdge = UIColor(white: 1, alpha: 0.22).cgColor
    private static let lightEdge = UIColor(white: 0, alpha: 0.10).cgColor
    private static let latchedGlyph = UIColor(Palette.accentInk)
    private static let glyphInk = UIColor(Palette.ink)

    /// The key's fill for its current state.
    static func fill(pressed: Bool, latched: Bool) -> UIColor {
        if latched { return pressed ? latchedPressedFill : latchedFill }
        if UIAccessibility.isReduceTransparencyEnabled {
            return pressed ? opaquePressedFill : opaqueRestFill
        }
        return pressed ? pressedFill : restFill
    }

    /// The hairline around a key, resolved for `traits` (a layer border takes a `CGColor`).
    static func edge(latched: Bool, traits: UITraitCollection) -> CGColor {
        if latched { return UIColor(Palette.accent).resolvedColor(with: traits).cgColor }
        return traits.userInterfaceStyle == .dark ? darkEdge : lightEdge
    }

    static func glyph(latched: Bool) -> UIColor {
        latched ? latchedGlyph : glyphInk
    }
}
#endif
