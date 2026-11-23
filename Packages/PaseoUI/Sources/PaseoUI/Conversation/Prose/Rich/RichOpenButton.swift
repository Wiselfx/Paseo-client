#if canImport(UIKit)
import SwiftUI

/// The full-width "Open" row under a card: the artifact page shows the whole thing, at any
/// width.
struct RichOpenButton: View {
    /// What VoiceOver says: it starts with the visible word, so Voice Control's "Tap Open" matches.
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: Metrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}
#endif
