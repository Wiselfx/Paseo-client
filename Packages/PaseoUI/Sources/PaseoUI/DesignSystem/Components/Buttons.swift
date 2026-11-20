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
extension ButtonStyle where Self == PrimaryButtonStyle {
    static func paseoPrimary(isWorking: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(isWorking: isWorking)
    }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var paseoSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
/// Published by `PressableRowStyle` so a row's leading seat can follow the finger. Defaults to
/// false everywhere else.
extension EnvironmentValues {
    @Entry var claudeRowPressed = false
}
/// The old name for `PressableRowStyle`.
@available(*, deprecated, message: "Use PressableRowStyle (.paseoRow)")
struct ClaudePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.claudeRowPressed, configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressableRowStyle {
    static var paseoRow: PressableRowStyle { PressableRowStyle() }
}
#Preview("Light") {
    VStack(spacing: Space.lg) {
        Button("Primary") {}.buttonStyle(.paseoPrimary())
        Button("Primary disabled") {}.buttonStyle(.paseoPrimary()).disabled(true)
        Button("Primary working") {}.buttonStyle(.paseoPrimary(isWorking: true))
        Button("Secondary") {}.buttonStyle(.paseoSecondary)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}
#Preview("Dark") {
    VStack(spacing: Space.lg) {
        Button("Primary") {}.buttonStyle(.paseoPrimary())
        Button("Primary disabled") {}.buttonStyle(.paseoPrimary()).disabled(true)
        Button("Primary working") {}.buttonStyle(.paseoPrimary(isWorking: true))
        Button("Secondary") {}.buttonStyle(.paseoSecondary)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
