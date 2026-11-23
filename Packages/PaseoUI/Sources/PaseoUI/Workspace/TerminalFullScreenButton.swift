#if canImport(UIKit)
import SwiftUI

/// Enters or leaves the terminal's full-screen mode. Outside full screen it is the chip bar's
/// trailing glass circle; inside it is the full-screen dock's last button. Same control, same
/// look in both places.
struct TerminalFullScreenButton: View {
    let isFullScreen: Bool
    let action: () -> Void

    var body: some View {
        TerminalGlassButton(
            title: isFullScreen ? "Exit Full Screen" : "Full Screen",
            systemImage: isFullScreen
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            identifier: "terminal.fullScreen",
            action: action)
    }
}
#endif
