#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Touch-down answers on the back-to-end circle: it scales in on `Motion.feedback` like the
/// rest of the app's buttons, and Reduce Motion switches instantly.
struct BackToEndPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}
#endif
