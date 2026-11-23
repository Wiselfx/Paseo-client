#if canImport(UIKit)
import SwiftUI

/// What went wrong with a piece of media, in the user's words, with the things worth doing
/// about it: Try again, and Open link when there is a web URL worth sending to Safari. The one
/// failure presentation for image, gallery, file, map and SVG cards, in the boxed form
/// (`MediaFailureBox`) and the compact row. Images are the default wording.
struct MediaFailureContent: View {
    /// The one line under the title: "host · what happened", or the path.
    let detail: String
    /// Nil hides the button: a failure that trying again cannot fix (a file over the cap).
    let onRetry: (() -> Void)?
    /// Only an http(s) link is worth sending to Safari; nil hides the button.
    var webURL: URL?
    /// Names the destination in the Open link hint.
    var host: String?
    var title = "Couldn't load image"
    var symbol = "photo"
    var retryHint = "Tries loading the image again"

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.paseo(.codeCaption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            // The visible word stays the accessibility label so Voice Control's "Tap Try again"
            // matches; the longer wording is a hint.
            if let onRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: Metrics.hitSize, minHeight: Metrics.hitSize)
                    .accessibilityHint(retryHint)
            }
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
