import UIKit

/// A zero-sized, inert view that writes the window's `overrideUserInterfaceStyle`.
final class WindowAppearanceView: UIView {
    var style: UIUserInterfaceStyle {
        didSet {
            guard style != oldValue else { return }
            apply()
        }
    }

    init(style: UIUserInterfaceStyle) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // The earliest moment the style can be known: before the first frame is drawn, so a
        // launch into Dark does not flash the system's light canvas.
        newWindow?.overrideUserInterfaceStyle = style
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply()
    }

    private func apply() {
        window?.overrideUserInterfaceStyle = style
    }
}
