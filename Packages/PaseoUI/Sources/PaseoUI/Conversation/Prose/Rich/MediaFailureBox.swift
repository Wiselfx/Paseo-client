#if canImport(UIKit)
import SwiftUI

/// The kept box with a failure inside it: the reader watched the placeholder, so the box keeps
/// the placeholder's height and only the inside is honest (H5 round 2 review — a 270 pt box
/// must not collapse to 56 pt under the reader).
struct MediaFailureBox<Content: View>: View {
    let aspect: CGFloat
    let width: CGFloat
    let heightCap: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        Rectangle()
            .fill(Palette.codeSurface)
            .aspectRatio(aspect, contentMode: .fit)
            .mediaSlot(width: width, heightCap: heightCap)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                content
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
            }
    }
}
#endif
