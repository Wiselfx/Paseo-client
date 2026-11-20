#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The fold over a long run's older steps: "12 earlier steps", on the rail, opening them.
struct WorkEarlierSteps: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            WorkStepFrame(
                icon: WorkIcon(kind: .more), rail: WorkRailPosition(above: false, below: true),
                highlighted: false
            ) {
                HStack(spacing: 6) {
                    Text("\(PaseoFormat.integer(count)) earlier steps")
                        .font(.paseo(.processTitle, weight: .medium))
                        .foregroundStyle(Palette.tertiaryInk)
                    Image(systemName: "chevron.up")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.captionInk)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: WorkTimelineMetrics.headerHeight)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(PaseoFormat.integer(count)) earlier steps")
    }
}
#endif
