#if canImport(UIKit)
import SwiftUI

/// A chip's pressed state: the label dims while the finger is down.
struct TerminalChipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? TerminalChrome.pressedOpacity : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
#endif
