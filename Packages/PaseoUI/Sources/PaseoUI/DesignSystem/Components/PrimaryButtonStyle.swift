#if canImport(UIKit)
import SwiftUI

/// The ink capsule: min height 44, `Space.xl` sides, callout semibold in the canvas color.
/// `isWorking` keeps the width and swaps the label for a spinner.
struct PrimaryButtonStyle: ButtonStyle {
    var isWorking = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            configuration.label
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.background)
                .padding(.horizontal, Space.xl)
                .frame(minHeight: 44)
                .opacity(isWorking ? 0 : 1)
            if isWorking {
                ProgressView().controlSize(.small).tint(Palette.background)
            }
        }
        .background(Palette.ink, in: .capsule)
        .opacity(isEnabled ? 1 : 0.4)
        .opacity(configuration.isPressed ? 0.85 : 1)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: configuration.isPressed)
        .allowsHitTesting(!isWorking)
    }
}
#endif
