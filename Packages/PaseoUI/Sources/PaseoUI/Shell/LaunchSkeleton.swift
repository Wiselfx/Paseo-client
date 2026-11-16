#if canImport(UIKit)
import SwiftUI

/// The shell's first frame while a saved host connects (R11 §1): the canvas and the hero, so a
/// cold launch to a saved host never flashes the connect form. It draws no session state and takes
/// no input; the real shell replaces it the moment the connect lands.
///
/// It is a splash, not an inert copy of the UI: **no header chrome and no sidebar button** (H4 §1).
/// It still uses the same `HomeHeroLayout` as the draft and `EmptyMain`, with the header's height
/// reserved by `HomeHeroHeaderSpacer` and the footer by `HomeHeroRestingFooter`, so the hero sits
/// exactly where the real screen draws it and the hand-off moves nothing.
public struct LaunchSkeleton: View {
    public init() {}

    public var body: some View {
        HomeHeroLayout {
            HomeHeroHeaderSpacer()
        } hero: {
            ClaudeHomeHero()
        }
        .background { Palette.background.ignoresSafeArea() }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connecting…")
    }
}

#Preview("Light") {
    LaunchSkeleton()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LaunchSkeleton()
        .preferredColorScheme(.dark)
}
#endif
