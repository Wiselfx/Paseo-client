#if canImport(UIKit)
import SwiftUI

/// A capsule chip for the compact buttons on the project page. The capsule keeps its compact
/// `visibleHeight`; the tap area around it reaches the 44pt minimum.
struct ProjectChip<Content: View>: View {
    let horizontalPadding: CGFloat
    let visibleHeight: CGFloat
    private let content: Content

    /// Nonisolated: `PhotosPicker` builds its label outside the main actor.
    nonisolated init(
        horizontalPadding: CGFloat = 14,
        visibleHeight: CGFloat = 36,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.visibleHeight = visibleHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: visibleHeight)
            .background(Palette.chip, in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
    }
}
#endif
