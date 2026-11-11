#if canImport(UIKit)
import SwiftUI

/// Metrics shared by the one home geometry (E2 §3).
enum HomeHeroMetrics {
    /// The home header's resting height: `ShellHeader`'s 48 pt row (its own `minHeight`). A page
    /// that draws no header — the launch frame — reserves exactly this, so the hero sits where
    /// the draft draws it and the hand-off moves nothing (H4 §1).
    static let headerHeight: CGFloat = 48
    /// The draft's resting chrome under the hero: its workspace line (28 pt + 4 pt) and its
    /// one-line composer (48 pt + 8 pt). Screens with no footer of their own reserve exactly this
    /// strip, so the greeting sits where the draft draws it and the hand-off moves nothing.
    static let draftChrome: CGFloat = 88
}

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
            header()
            hero()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The blank strip that stands in for the home header: the same height, no chrome and no
/// button, so a launch frame reserves the header's space without drawing any of it (H4 §1).
struct HomeHeroHeaderSpacer: View {
    var body: some View {
        Color.clear.frame(height: HomeHeroMetrics.headerHeight)
    }
}
#endif
