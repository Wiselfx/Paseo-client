#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The touch-down answer every composer button gives: scale to 0.92 on the way down, back on the
/// way up, through `Motion.feedback` (D2 §1).
struct ComposerPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}
#endif
