#if canImport(UIKit)
import SwiftUI

/// What went wrong with an image, in the user's words, with the things worth doing about it:
/// Retry, and Open link when there is a web URL worth sending to Safari. Shared by the remote
/// and local image cards, in the boxed form (`MediaFailureBox`) and the compact row.
struct MediaFailureContent: View {
    /// The one line under the title: "host · what happened", or the path.
    let detail: String
    let onRetry: () -> Void
    /// Only an http(s) link is worth sending to Safari; nil hides the button.
    var webURL: URL?
    /// Names the destination in the Open link hint.
    var host: String?

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: "photo")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Couldn't load image")
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            // The visible word stays the accessibility label so Voice Control's "Tap Retry"
            // matches; the longer wording is a hint.
            Button("Retry", action: onRetry)
                .buttonStyle(.plain)
                .font(.paseo(.caption, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                .accessibilityHint("Tries loading the image again")
            if let webURL {
                Button {
                    openURL(webURL)
                } label: {
                    Image(systemName: "safari")
                        .font(.glyph(.small))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open link")
                .accessibilityHint("Opens \(host ?? "the link") in Safari")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
