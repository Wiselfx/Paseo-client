#if canImport(UIKit)
import SwiftUI

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
