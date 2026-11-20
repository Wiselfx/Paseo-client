#if canImport(UIKit)
import SwiftUI

/// A trailing chevron, 12 × 12, turning down while its row is open.
struct ClaudeChevron: View {
    var expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.glyph(.small, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}
#endif
