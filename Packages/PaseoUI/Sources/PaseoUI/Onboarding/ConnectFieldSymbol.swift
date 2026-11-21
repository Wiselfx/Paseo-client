#if canImport(UIKit)
import SwiftUI

/// The leading glyph of a Connect form row.
struct ConnectFieldSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.glyph(.regular, weight: .light))
            .foregroundStyle(Palette.tertiaryInk)
            .frame(width: 23)
            // Decorative: the field's own title names the row for VoiceOver.
            .accessibilityHidden(true)
    }
}
#endif
