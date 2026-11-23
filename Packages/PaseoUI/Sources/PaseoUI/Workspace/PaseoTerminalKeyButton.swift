#if canImport(UIKit)
import UIKit

/// One key of `PaseoTerminalKeyBar`: a rounded translucent key (`TerminalKeyStyle`) that lights up
/// and shrinks the instant the finger lands, and an activation that works for VoiceOver and
/// Switch Control (which never send touches).
///
/// A press changes the fill and the transform only: no layout, no animation on the way down.
final class KeyButton: UIButton {
    /// What the key does; the bar sets it and calls it for a press, a repeat, and VoiceOver.
    var onActivate: ((UIButton) -> Void)?

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            showPress()
        }
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            refreshColors()
        }
    }

    /// Call once after creating the key with `UIButton(type:)`, which skips `init(frame:)`.
    func applyStyle() {
        layer.cornerRadius = TerminalKeyStyle.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = TerminalKeyStyle.hairline
        refreshColors()
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (key: KeyButton, _: UITraitCollection) in
            key.refreshColors()
        }
    }

    /// Fill, edge and glyph for the current state. Also run when the bar comes on screen, so a
    /// Reduce Transparency change made meanwhile is picked up.
    func refreshColors() {
        backgroundColor = TerminalKeyStyle.fill(pressed: isHighlighted, latched: isSelected)
        layer.borderColor = TerminalKeyStyle.edge(latched: isSelected, traits: traitCollection)
        let glyph = TerminalKeyStyle.glyph(latched: isSelected)
        tintColor = glyph
        setTitleColor(glyph, for: .normal)
    }

    override func accessibilityActivate() -> Bool {
        onActivate?(self)
        return true
    }

    private func showPress() {
        backgroundColor = TerminalKeyStyle.fill(pressed: isHighlighted, latched: isSelected)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if isHighlighted {
            // Instant: the key answers the finger on the frame it lands.
            transform = CGAffineTransform(
                scaleX: TerminalKeyStyle.pressedScale, y: TerminalKeyStyle.pressedScale)
        } else {
            UIView.animate(
                withDuration: TerminalKeyStyle.releaseDuration, delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = .identity
            }
        }
    }
}
#endif
