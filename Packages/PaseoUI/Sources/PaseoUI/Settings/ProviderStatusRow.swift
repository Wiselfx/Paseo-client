#if canImport(UIKit)
import SwiftUI

/// One icon, title and detail line in the provider status group.
struct ProviderStatusRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(Palette.tertiaryInk)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.paseo(.body))
                Text(detail)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.lg)
        .frame(minHeight: 52)
    }
}
#endif
