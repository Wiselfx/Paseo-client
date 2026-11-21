#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The frame every step shares: the icon on the rail, the content beside it, the find wash behind.
struct WorkStepFrame<Content: View>: View {
    let icon: WorkIcon
    let rail: WorkRailPosition
    let highlighted: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: WorkTimelineMetrics.gutter - WorkTimelineMetrics.nodeSize) {
            icon.frame(height: WorkTimelineMetrics.headerHeight)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
        .background(alignment: .topLeading) { WorkRail(position: rail) }
        .background { FindWash(highlighted: highlighted, bleed: 4) }
    }
}
#endif
