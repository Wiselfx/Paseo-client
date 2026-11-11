#if canImport(UIKit)
import SwiftUI

/// The shell's first frame while a saved host connects (R11 §1): the canvas, the header and the
/// empty main, so a cold launch to a saved host never flashes the connect form. It draws no
/// session state and takes no input; the real shell replaces it the moment the connect lands.
///
/// It uses the same `HomeHeroLayout` as `EmptyMain`, with the sidebar button already in its final
/// position and inert, so the hand-off from launch to the shell moves nothing (E2 §3).
public struct LaunchSkeleton: View {
    public init() {}

    public var body: some View {
        HomeHeroLayout {
            ShellHeader(leading: .sidebar({})) {
                Color.clear
            } trailing: {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
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
