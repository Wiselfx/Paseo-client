#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// The media-card layout (G1 §1.1): the media slot sits on top, edge to edge and clipped to
/// the card, and an optional header strip goes below. With no header the media *is* the card
/// (C1: no metadata strip on images) — the panel never insets the pixels.
struct PaseoMediaCard<Media: View>: View {
    let media: Media
    let header: PaseoCardHeader?

    init(media: Media, header: PaseoCardHeader? = nil) {
        self.media = media
        self.header = header
    }

    var body: some View {
        VStack(spacing: 0) {
            media
            if let header {
                header
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        }
    }
}
#endif
