#if canImport(UIKit)
import SwiftUI

/// Metrics shared by the one home geometry (E2 §3).
enum HomeHeroMetrics {
    /// The draft's resting chrome under the hero: its workspace line (28 pt + 4 pt) and its
    /// one-line composer (48 pt + 8 pt). Screens with no footer of their own reserve exactly this
    /// strip, so the greeting sits where the draft draws it and the hand-off moves nothing.
    static let draftChrome: CGFloat = 88
}

/// The home page's geometry, in one place: the header attached as a top bar, a flexible hero, and
/// the page's own footer under it — never a stack hugging its content in the middle of the screen
/// (the floating sidebar button, E2 §3).
///
/// `DraftChatView` passes its real workspace line + composer (or the Add project action) as the
/// footer; `LaunchSkeleton` and `EmptyMain` pass `HomeHeroRestingFooter`, which reserves the same
/// resting strip. One structure, so the hero box is identical in every state.
struct HomeHeroLayout<Header: View, Hero: View, Footer: View>: View {
    private let header: () -> Header
    private let hero: () -> Hero
    private let footer: () -> Footer

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder hero: @escaping () -> Hero,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.header = header
        self.hero = hero
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            hero()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) { header() }
    }
}

extension HomeHeroLayout where Footer == HomeHeroRestingFooter {
    /// A home with no footer yet (launching, or no agent/draft to show): reserve the draft's
    /// resting chrome so the hero does not move when the final screen arrives.
    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder hero: @escaping () -> Hero
    ) {
        self.init(header: header, hero: hero) { HomeHeroRestingFooter() }
    }
}

/// The blank strip that stands in for the draft's workspace line and resting composer.
struct HomeHeroRestingFooter: View {
    var body: some View {
        Color.clear.frame(height: HomeHeroMetrics.draftChrome)
    }
}
#endif
