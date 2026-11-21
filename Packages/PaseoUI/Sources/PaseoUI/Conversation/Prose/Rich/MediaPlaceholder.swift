#if canImport(UIKit)
import SwiftUI

/// The box a media card reserves before its pixels arrive: a spinner, or a determinate ring
/// when the download's total is known, at the card's aspect ratio and slot width so the
/// reader's place in the transcript does not move when the image lands.
struct MediaPlaceholder: View {
    let aspect: CGFloat
    let width: CGFloat
    let heightCap: CGFloat
    /// The last streaming progress, or nil before the first event (or when the total is
    /// unknown): the indeterminate spinner instead.
    let progress: Double?
    let alt: String

    var body: some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(aspect, contentMode: .fit)
            .mediaSlot(width: width, heightCap: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                // Streaming with a known total: the determinate ring in the same frame.
                if let progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .tint(Palette.secondaryInk)
                } else {
                    ProgressView().controlSize(.small).tint(Palette.secondaryInk)
                }
            }
            .accessibilityLabel(alt.isEmpty ? "Loading image" : "Loading image: \(alt)")
    }
}
#endif
