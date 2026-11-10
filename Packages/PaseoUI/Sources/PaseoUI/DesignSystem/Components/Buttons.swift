#if canImport(UIKit)
import SwiftUI

/// The ink capsule: min height 44, `Space.xl` sides, callout semibold in the canvas color.
/// `isWorking` keeps the width and swaps the label for a spinner.
struct PrimaryButtonStyle: ButtonStyle {
    var isWorking = false
    @Environment(\.isEnabled) private var isEnabled

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
        .animation(Motion.feedback.animation, value: configuration.isPressed)
        .allowsHitTesting(!isWorking)
    }
}

/// The chip capsule: the same shape and metrics, `Palette.chip` fill and ink text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.paseo(.callout, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Space.xl)
            .frame(minHeight: 44)
            .background(Palette.chip, in: .capsule)
            .opacity(isEnabled ? 1 : 0.4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.feedback.animation, value: configuration.isPressed)
    }
}

/// Full-width rows: a `Palette.chip` wash over the row's own shape while the finger is down,
/// and `\.claudeRowPressed` published for rows that follow the press.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Palette.chip.opacity(configuration.isPressed ? 1 : 0),
                in: .rect(cornerRadius: Radius.md)
            )
            .environment(\.claudeRowPressed, configuration.isPressed)
            .animation(Motion.feedback.animation, value: configuration.isPressed)
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
private struct ClaudeRowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var claudeRowPressed: Bool {
        get { self[ClaudeRowPressedKey.self] }
        set { self[ClaudeRowPressedKey.self] = newValue }
    }
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
