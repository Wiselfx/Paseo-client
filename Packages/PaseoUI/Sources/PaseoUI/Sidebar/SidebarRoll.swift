#if canImport(UIKit)
import SwiftUI

/// The height roll for a project's workspace rows: 200 ms, ease-out, measured naturally.
struct SidebarRoll<Content: View>: View {
    let expanded: Bool
    @ViewBuilder var content: () -> Content

    /// The last measured content height, remembered across collapses so an expanded roll has
    /// an animation target before its first measurement lands (P5 finding #3).
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        contentOrEmpty
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: expanded)
    }

    /// Collapsed rolls build no rows. The content used to stay mounted (and measured) even
    /// when the frame was 0, so a project with hundreds of workspaces mounted them all
    /// (P5 finding #3). The height is measured only while expanded and cached for the
    /// collapse/expand animation.
    @ViewBuilder private var contentOrEmpty: some View {
        if expanded {
            content()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
        }
    }
}
#endif
