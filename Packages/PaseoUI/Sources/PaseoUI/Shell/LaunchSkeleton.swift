#if canImport(UIKit)
import SwiftUI

/// The shell's first frame while a saved host connects (R11 §1): the canvas, the header and the
/// empty main, so a cold launch to a saved host never flashes the connect form. It draws no
/// session state and takes no input; the real shell replaces it the moment the connect lands.
public struct LaunchSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ShellHeader(leading: .none) {
                Color.clear
            } trailing: {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            ClaudeHomeHero()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
        .ignoresSafeArea(edges: .bottom)
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
