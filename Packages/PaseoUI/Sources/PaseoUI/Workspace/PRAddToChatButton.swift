#if canImport(UIKit)
import SwiftUI

/// The small "@ Add to chat" action under a review or comment.
struct PRAddToChatButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: "at")
                    .font(.glyph(.small, weight: .medium))
                Text("Add to chat")
                    .font(.paseo(.caption, weight: .medium))
            }
            .foregroundStyle(Palette.secondaryInk)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to chat")
    }
}
#endif
