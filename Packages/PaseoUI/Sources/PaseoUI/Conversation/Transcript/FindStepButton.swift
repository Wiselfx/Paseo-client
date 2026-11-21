#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// An icon-only chevron in the find bar: the title is the Voice Control and VoiceOver name, and
/// the 44 pt hit area lives inside the label so the plain button style keeps it.
struct FindStepButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 26, height: 30)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
#endif
