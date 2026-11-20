#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Upstream's `SettingsInfoTip`: an info icon in the title that opens the explanation. A popover,
/// not a paragraph under the row, so the row stays one line (UX-SPEC §0.3).
struct SettingsInfoButton: View {
    let title: String
    let info: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.glyph(.small))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isPresented) {
            Text(info)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.xl)
                .frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }
}
#endif
