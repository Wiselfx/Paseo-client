#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The rail through one step: from the step's top to just above its node, and from just below the
/// node to the step's bottom (through whatever the step opened). Every step draws its own piece, so
/// no step needs to know where another one is.
struct WorkRail: View {
    let position: WorkRailPosition

    var body: some View {
        let center = WorkTimelineMetrics.headerHeight / 2
        let radius = WorkTimelineMetrics.nodeSize / 2 + WorkTimelineMetrics.railGap
        VStack(spacing: 0) {
            Rectangle()
                .fill(position.above ? Palette.divider : .clear)
                .frame(width: 1, height: max(center - radius, 0))
            Color.clear.frame(width: 1, height: radius * 2)
            Rectangle()
                .fill(position.below ? Palette.divider : .clear)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: WorkTimelineMetrics.nodeSize)
        .accessibilityHidden(true)
    }
}
#endif
