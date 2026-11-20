#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A stable identity for the mounted page, so `.onDisappear` fires when the panel closes or the
/// workspace changes, but not when the selected tab changes.
struct PanelPage<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View { content() }
}
#endif
