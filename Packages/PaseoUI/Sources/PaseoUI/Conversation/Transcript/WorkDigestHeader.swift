#if canImport(UIKit)
import SwiftUI

/// The one line a work section shows folded: its icon, its title, the chevron. Always the same
/// height, so a section that streams while folded never moves the transcript.
struct WorkDigestHeader<Title: View>: View {
    let icon: WorkIcon
    let isOpen: Bool
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let title: Title

    var body: some View {
        Button(action: action) {
            HStack(spacing: WorkTimelineMetrics.gutter - WorkTimelineMetrics.nodeSize) {
                icon
                title
                    .frame(maxWidth: .infinity, alignment: .leading)
                ClaudeTurnChevron(expanded: isOpen)
            }
            .frame(minHeight: WorkTimelineMetrics.headerHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }
}
#endif
