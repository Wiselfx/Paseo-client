#if canImport(UIKit)
import SwiftUI

/// The header row the diagram, SVG and web cards share: the card's title and a capsule toggle
/// between the rendered stage and its source. The capsule is drawn at caption size, but its
/// tap area is the full 44 pt target.
struct RichCardSourceHeader: View {
    let title: String
    @Binding var showSource: Bool
    /// What the toggle says while the source is showing: "Hide source", or "View diagram" for
    /// a card whose stage is a diagram.
    var hideLabel = "Hide source"

    var body: some View {
        HStack {
            Text(title)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            Button(action: toggleSource) {
                Text(showSource ? hideLabel : "View source")
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.vertical, Metrics.cardHeaderVPadding)
                    .padding(.horizontal, Metrics.cardHeaderHPadding)
                    .overlay { Capsule().strokeBorder(Palette.cardBorder, lineWidth: 0.5) }
                    .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleSource() {
        showSource.toggle()
    }
}
#endif
