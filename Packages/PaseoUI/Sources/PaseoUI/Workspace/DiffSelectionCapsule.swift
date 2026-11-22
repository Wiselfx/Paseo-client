#if canImport(UIKit)
import SwiftUI

/// The floating capsule while a line range is selected: "Comment on N lines" and clear.
struct DiffSelectionCapsule: View {
    let count: Int
    let onComment: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: onComment) {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.glyph(.small, weight: .medium))
                    Text("Comment on ^[\(count) line](inflect: true)")
                        .font(.paseo(.footnote, weight: .medium))
                }
                .foregroundStyle(Palette.background)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Palette.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Comment on the selected ^[\(count) line](inflect: true)"))
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 38, height: 38)
                    .frame(width: 44, height: 44)
                    .background(Palette.ink.opacity(0.85), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
    }
}
#endif
