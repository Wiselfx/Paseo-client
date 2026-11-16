import PaseoUI
import SwiftUI
import UIKit

/// Applies the Appearance setting to the window the app is drawn in (H4 §3).
///
/// `.preferredColorScheme` only reaches the SwiftUI tree that hosts it. A Settings sheet is its
/// own hosting controller, so a change made *while that sheet is open* left the sheet in the old
/// mode until it was re-presented, and "System" (`nil`) never went back to following the OS.
/// `window.overrideUserInterfaceStyle` is the trait every view — and every presented sheet — in
/// that window inherits, so one value per window covers the whole app immediately, with the
/// system's own cross-fade.
///
/// The view is zero-sized. It exists to find its window: `willMove(toWindow:)` applies the style
/// before the first frame, `didMoveToWindow` on every window change, and `updateUIView` on later
/// changes.
struct WindowAppearance: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> WindowAppearanceView {
        WindowAppearanceView(style: style)
    }

    func updateUIView(_ view: WindowAppearanceView, context: Context) {
        view.style = style
    }
}

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

extension UIUserInterfaceStyle {
    /// The window style for an Appearance choice. `.unspecified` is "System": the only value
    /// that really returns to following the OS. Derived from `ClaudeAppearance.colorScheme` so the
    /// app has one statement of which scheme each choice is (Pure black is a dark scheme).
    init(_ appearance: ClaudeAppearance) {
        switch appearance.colorScheme {
        case .some(.light): self = .light
        case .some: self = .dark
        case nil: self = .unspecified
        }
    }
}
