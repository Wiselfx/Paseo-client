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
