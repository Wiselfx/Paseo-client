#if canImport(UIKit)
import SwiftUI

/// The §12 tap state: the reserved box, the size when known, one tap to fetch.
struct VideoTapToDownloadBox: View {
    /// "Tap to download", with the size when it is known.
    let label: String
    let fileName: String
    let aspect: CGFloat
    let slotWidth: CGFloat
    let heightCap: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Rectangle()
                .fill(Palette.codeSurface)
                .aspectRatio(aspect, contentMode: .fit)
                .mediaSlot(width: slotWidth, heightCap: heightCap)
                .overlay {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "arrow.down.circle")
                            .font(.glyph(.large, weight: .light))
                            .foregroundStyle(Palette.secondaryInk)
                        Text(label)
                            .font(.paseo(.caption, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(fileName)
                            .font(.paseo(.codeCaption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Space.md)
                }
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Download video \(fileName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Downloads the video")
    }
}
#endif
