#if canImport(UIKit)
import SwiftUI

/// The last row of the agent profiles list: opens the create sheet.
struct AddProfileRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: "plus.circle")
                    .font(.glyph(.large, weight: .light))
                    .foregroundStyle(Palette.ink)
                Text("Add profile")
                    .font(.paseo(.body))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.profiles.add")
    }
}
#endif
