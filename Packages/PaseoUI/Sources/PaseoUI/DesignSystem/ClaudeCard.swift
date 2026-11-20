#if canImport(UIKit)
import SwiftUI

/// Rounded card with the 1 pt edge the process column uses.
struct ClaudeCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
    }
}
#endif
