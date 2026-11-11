#if canImport(UIKit)
import SwiftUI

/// Metrics shared by the one home geometry (E2 §3).
enum HomeHeroMetrics {
    /// The draft's resting chrome under the hero: its workspace line (28 pt + 4 pt) and its
    /// one-line composer (48 pt + 8 pt). `HomeHeroLayout` reserves exactly this strip, so the
    /// greeting sits where the draft will draw it and the hand-off moves nothing.
    static let draftChrome: CGFloat = 88
}

/// The home page's geometry, in one place: the header attached as a top bar and the hero centred
/// in the rest — never a stack hugging its content in the middle of the screen (the floating
/// sidebar button, E2 §3).
///
/// The structure mirrors `DraftChatView.column`: a flexible stage over a fixed bottom strip, with
/// the header in a top `safeAreaBar`. Whatever that bar does to the content's safe area, the
/// skeleton, the empty main and the draft measure the same hero box.
struct HomeHeroLayout<Header: View, Hero: View>: View {
    private let header: () -> Header
    private let hero: () -> Hero

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder hero: @escaping () -> Hero
    ) {
        self.header = header
        self.hero = hero
    }

    var body: some View {
        VStack(spacing: 0) {
            hero()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The draft's workspace line and composer will occupy this strip.
            Color.clear.frame(height: HomeHeroMetrics.draftChrome)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) { header() }
    }
}
#endif
