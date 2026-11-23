#if canImport(UIKit)
import SwiftUI
import UIKit

/// One key of `PaseoTerminalKeyBar`: a system button with a rounded highlight while it is pressed
/// or latched, and an activation that works for VoiceOver and Switch Control (the key itself
/// fires on touch-down, which assistive technologies never send).
final class KeyButton: UIButton {
    /// What the key does; the bar sets it and calls it for a press, a repeat, and VoiceOver.
    var onActivate: ((UIButton) -> Void)?

    override var isHighlighted: Bool { didSet { updateHighlight() } }
    override var isSelected: Bool { didSet { updateHighlight() } }

    override func accessibilityActivate() -> Bool {
        onActivate?(self)
        return true
    }

    private func updateHighlight() {
        backgroundColor = isHighlighted || isSelected ? UIColor(Palette.chip) : .clear
    }
}
#endif
