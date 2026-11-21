#if canImport(UIKit)
import SwiftUI

/// The home page's geometry, in one place: the header as the page's first row, a flexible hero,
/// and the page's own footer under it — never a stack hugging its content in the middle of the
/// screen (the floating sidebar button, E2 §3).
///
/// The header is a **row of the stack**, not a `safeAreaBar`: a bar is a scroll-edge effect that
/// insets only the safe area and leaves a non-scrolling stack to fill the parent's full frame, so
/// on device the header drifted into the middle of the screen (H4 §1). A row is pinned by the
/// stack: top-leading, every time, with no bar machinery.
///
/// `DraftChatView` passes its real workspace line + composer (or the Add project action) as the
/// footer; `LaunchSkeleton` and `EmptyMain` pass `HomeHeroRestingFooter`, which reserves the same
/// resting strip. One structure, so the hero box is identical in every state.
struct HomeHeroLayout<Header: View, Hero: View, Footer: View>: View {
    // The built views, not escaping closures: the layout keeps the values it draws, built once
    // where the layout is created.
    private let header: Header
    private let hero: Hero
    private let footer: Footer

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.hero = hero()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            hero
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
extension HomeHeroLayout where Footer == HomeHeroRestingFooter {
    /// A home with no footer yet (launching, or no agent/draft to show): reserve the draft's
    /// resting chrome so the hero does not move when the final screen arrives.
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder hero: () -> Hero
    ) {
        self.init(header: header, hero: hero) { HomeHeroRestingFooter() }
    }
}
#endif
