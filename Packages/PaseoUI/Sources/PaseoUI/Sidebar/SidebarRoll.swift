#if canImport(UIKit)
import SwiftUI

/// The height roll for a project's workspace rows: 200 ms, ease-out, measured naturally.
struct SidebarRoll<Content: View>: View {
    let expanded: Bool
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SidebarRollHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(SidebarRollHeightKey.self) { contentHeight = $0 }
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move), value: expanded)
    }
}

struct SidebarRollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif
