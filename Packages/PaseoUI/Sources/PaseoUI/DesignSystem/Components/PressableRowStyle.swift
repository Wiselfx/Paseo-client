#if canImport(UIKit)
import SwiftUI

/// Full-width rows: a `Palette.chip` wash over the row's own shape while the finger is down,
/// and `\.claudeRowPressed` published for rows that follow the press.
struct PressableRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Palette.chip.opacity(configuration.isPressed ? 1 : 0),
                in: .rect(cornerRadius: Radius.md)
            )
            .environment(\.claudeRowPressed, configuration.isPressed)
            .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
#endif
