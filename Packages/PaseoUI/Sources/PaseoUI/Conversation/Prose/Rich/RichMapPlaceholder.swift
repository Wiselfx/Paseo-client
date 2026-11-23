#if canImport(UIKit)
import SwiftUI

/// The map snapshot slot's content before there is an image: a spinner while the render runs,
/// the map glyph with a line when it cannot (offline, failed), the bare glyph for a query-only
/// link that has no coordinates to render.
struct RichMapPlaceholder: View {
    let showsProgress: Bool
    let message: String?

    var body: some View {
        VStack(spacing: Space.sm) {
            if showsProgress {
                ProgressView().controlSize(.small).tint(Palette.secondaryInk)
            } else {
                Image(systemName: "map")
                    .font(.glyph(.xlarge, weight: .light))
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            if let message {
                Text(message)
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}
#endif
