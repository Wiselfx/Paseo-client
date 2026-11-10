#if canImport(UIKit)
import SwiftUI

/// M8d: the shared chrome for the composer popovers (slash commands, file mentions). Same look:
/// rounded panel, hairline border, same width as the card, max height set by the caller.
struct ComposerMenuContainer<Content: View>: View {
    var accessibilityIdentifier: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group { content() }
            .frame(maxWidth: .infinity)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
            }
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
#endif
