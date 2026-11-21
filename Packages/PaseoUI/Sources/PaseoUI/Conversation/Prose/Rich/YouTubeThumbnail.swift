#if canImport(UIKit)
import SwiftUI
import UIKit

/// The YouTube card's face before playback: the still (or its placeholder) with a play glyph, as
/// one plain button. The still itself is loaded by the card and handed in.
struct YouTubeThumbnail: View {
    let still: UIImage?
    let failed: Bool
    /// What VoiceOver says: "Play" plus the video's title when it is known.
    let accessibilityText: String
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack {
                if let still {
                    Image(uiImage: still)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Palette.codeSurface)
                        .overlay {
                            if failed {
                                Image(systemName: "photo")
                                    .font(.glyph(.xlarge, weight: .light))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                }

                Circle()
                    .fill(Palette.mediaBadge)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.glyph(.regular, weight: .semibold))
                            .foregroundStyle(Palette.onMediaBadge)
                            .offset(x: 1)
                    }
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}
#endif
