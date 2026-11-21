#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Output tokens and cost per turn, last 30, live turns only: the series starts
/// where data starts, never with fake zeros for older turns. Both boxes are
/// reserved from the first frame whether or not any turn has been observed.
struct ContextTurnChartsSection: View {
    let points: [TurnUsagePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ContextSectionLabel(title: "Usage per turn")
            if points.isEmpty {
                Text("Per-turn charts appear as turns complete.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Metrics.turnChartHeight)
                    .padding(.horizontal, Space.lg)
            } else {
                OutputPerTurnChart(points: points)
                CostPerTurnChart(points: points)
            }
        }
    }
}
#endif
