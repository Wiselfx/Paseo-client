#if canImport(UIKit)
import SwiftUI

/// Text that scrolls under the composer dissolves instead of showing sharp around the card: a
/// material that fades in from just above the card and runs down through the home-indicator
/// strip. It sits behind the bar, so it follows the composer's growth and the keyboard, and it
/// never takes a touch.
struct ComposerUnderBlur: View {
    /// How far above the bar the dissolve starts, so lines soften before they reach the card.
    private static let lead: CGFloat = 28

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.7), location: 0.35),
                        .init(color: .black, location: 0.7),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .padding(.top, -Self.lead)
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
