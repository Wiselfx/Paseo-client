#if canImport(UIKit)
import SwiftUI

/// The chip capsule: the same shape and metrics, `Palette.chip` fill and ink text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.paseo(.callout, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.xl)
            .frame(minHeight: 44)
            .background(Palette.chip, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
#endif
