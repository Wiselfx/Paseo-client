#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// A thin progress bar for the sidebar's usage lines and the reports sheet's window rows:
/// track in `tertiaryInk`, fill in ink, rounded ends. One height everywhere and the width is the
/// caller's business, so two rows of the same surface can never draw different bars.
struct ClaudeUsageBar: View {
    let percent: Double
    var width: CGFloat = SidebarMetrics.usageMeterWidth
    var height: CGFloat = SidebarMetrics.usageMeterHeight

    private var clamped: Double { min(max(percent, 0), 100) }

    var body: some View {
        Capsule()
            .fill(Palette.tertiaryInk.opacity(0.35))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(ClaudeMeterRing.meterColor)
                    .frame(width: width * CGFloat(clamped / 100), height: height)
            }
            .accessibilityHidden(true)
    }
}
#endif
