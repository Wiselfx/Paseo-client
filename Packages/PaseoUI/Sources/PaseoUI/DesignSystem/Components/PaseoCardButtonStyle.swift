#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Press

/// The card press (G1 §1.2): the content settles to 98 % while held, through the feedback
/// token. `reduceMotion` is a value (R-2): the host reads the environment once and passes it
/// in, so the style itself observes nothing.
struct PaseoCardButtonStyle: ButtonStyle {
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Metrics.cardPressScale : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}
#endif
