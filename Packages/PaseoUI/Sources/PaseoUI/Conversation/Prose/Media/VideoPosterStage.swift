#if canImport(UIKit)
import SwiftUI
import UIKit

/// The video card's poster: the first frame with a play badge and the duration, one Button
/// that starts playback in place.
struct VideoPosterStage: View {
    let poster: UIImage
    let duration: Double?
    /// The reserved box: ratio, the prose column's width and the viewport height cap.
    let aspect: CGFloat
    let slotWidth: CGFloat
    let heightCap: CGFloat
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .mediaSlot(width: slotWidth, heightCap: heightCap)
                    .clipped()
                Circle()
                    .fill(Palette.mediaBadge)
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.paseo(.body, weight: .semibold))
                            .foregroundStyle(Palette.onMediaBadge)
                            .offset(x: 1)
                            .accessibilityHidden(true)
                    }
                if let duration {
                    Text(VideoCard.timestamp(duration))
                        .font(.paseo(.caption, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.onMediaBadge)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Metrics.overlayVPadding)
                        .background(Palette.mediaBadge, in: .capsule)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(Space.sm)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .mediaSlot(width: slotWidth, heightCap: heightCap)
            .clipped()
            .contentShape(.rect)
        }
        .buttonStyle(PaseoCardButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Play video")
    }
}
#endif
