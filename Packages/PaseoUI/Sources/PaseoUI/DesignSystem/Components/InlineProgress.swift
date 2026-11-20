#if canImport(UIKit)
import SwiftUI

/// The small spinner a row or button embeds.
struct InlineProgress: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(Palette.secondaryInk)
    }
}
#endif
