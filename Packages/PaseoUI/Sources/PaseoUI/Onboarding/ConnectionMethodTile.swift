#if canImport(UIKit)
import SwiftUI

/// One connection method (Direct / Scan QR code / Paste pairing link) as a tappable tile. Shared by
/// the first-run `WelcomeView` and the `AddHostMethodsSheet`, so the same choice looks the same
/// wherever it is opened.
struct ConnectionMethodTile: View {
    let title: String
    let description: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.background)
                    .frame(width: 34, height: 34)
                    .background(Palette.ink, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paseo(.body, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text(description)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.glyph(.regular))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Space.md)
            // A minimum, not a fixed height: the two-line text grows with Dynamic Type.
            .frame(minHeight: 68)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
#endif
