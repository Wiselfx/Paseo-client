#if canImport(UIKit)
import SwiftUI

/// The honest failure: the reserved box, one line, and Try again in place.
struct VideoLoadFailureBox: View {
    let fileName: String
    let aspect: CGFloat
    let slotWidth: CGFloat
    let heightCap: CGFloat
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(aspect, contentMode: .fit)
                .mediaSlot(width: slotWidth, heightCap: heightCap)
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "film")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text("Couldn't load video")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("Try again")
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.accentInk)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Couldn't load video \(fileName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Retries loading the video")
    }
}
#endif
