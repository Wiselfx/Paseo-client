#if canImport(UIKit)
import SwiftUI

/// The viewer's top bar: Close on the leading edge, the page counter (or the file name, for a
/// lone page) centred.
struct MediaViewerTopBar: View {
    /// The 0-based current page and the page total.
    let position: Int
    let count: Int
    /// The current page's file name; nil when there is no page.
    let fileName: String?
    /// The spoken page label ("Image 2 of 5, alt").
    let announcement: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onClose) {
                Label("Close viewer", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.paseo(.body))
                    .frame(width: Metrics.hitSize, height: Metrics.hitSize)
                    .contentShape(.circle)
            }
            .glassEffect(in: .circle)
            .accessibilityIdentifier("media.viewer.close")
            Spacer(minLength: Space.sm)
            if count > 1, fileName != nil {
                Text("\(position + 1) of \(count)")
                    .font(.paseo(.footnote))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityLabel(announcement)
                    .accessibilityAddTraits(.isHeader)
            } else if let fileName {
                Text(fileName)
                    .font(.paseo(.footnote))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            // Balance: the close circle's width, so a lone title stays centred.
            Color.clear.frame(width: Metrics.hitSize, height: Metrics.hitSize)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.md)
    }
}
#endif
