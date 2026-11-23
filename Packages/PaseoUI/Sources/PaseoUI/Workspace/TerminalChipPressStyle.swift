#if canImport(UIKit)
import SwiftUI

/// A chip's pressed state: the label dims on the frame the finger lands, and eases back on release.
struct TerminalChipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? TerminalChrome.pressedOpacity : 1)
            // No animation on the way down, so the press shows at once.
            .animation(
                configuration.isPressed
                    ? nil : Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}
#endif
