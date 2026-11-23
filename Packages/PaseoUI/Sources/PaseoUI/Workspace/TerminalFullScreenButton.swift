#if canImport(UIKit)
import SwiftUI

/// Enters or leaves the terminal's full-screen mode. Outside full screen it sits at the end of
/// the chip bar; inside it floats over the terminal's top-trailing corner, the only chrome left.
struct TerminalFullScreenButton: View {
    let isFullScreen: Bool
    let action: () -> Void

    var body: some View {
        Button(
            isFullScreen ? "Exit Full Screen" : "Full Screen",
            systemImage: isFullScreen
                ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            action: action
        )
        .labelStyle(.iconOnly)
        .font(.glyph(.small, weight: .medium))
        .foregroundStyle(Palette.ink)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .accessibilityIdentifier("terminal.fullScreen")
    }
}
#endif
