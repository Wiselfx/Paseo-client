#if canImport(UIKit)
import SwiftUI

/// The line under a full-size YouTube card: the oEmbed title when known, the channel (or the
/// domain fallback), and a Close button while the video plays. The card fetches the title and
/// hands in whatever it has.
struct YouTubeTitleStrip: View {
    let title: String?
    let channel: String?
    let id: String
    let isPlaying: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                // The channel when known, nothing while the title loads or when offline:
                // a bare "youtube.com · <id>" says nothing a reader can use.
                if let channel {
                    Image(systemName: "play")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .accessibilityHidden(true)
                    Text(channel)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isPlaying {
                    Button("Close", action: onClose)
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .buttonStyle(.plain)
                        .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                        .contentShape(.rect)
                }
            }
        }
        .padding(.horizontal, Space.xs)
    }
}
#endif
