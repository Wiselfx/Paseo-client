#if canImport(UIKit)
import Charts
import PaseoStore
import SwiftUI

/// Cost per turn in neutral ink: the output chart owns the one accent.
struct CostPerTurnChart: View {
    let points: [TurnUsagePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Cost per turn")
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Chart(Array(points.enumerated()), id: \.offset) { index, point in
                BarMark(
                    x: .value("Turn", index + 1),
                    y: .value("Cost", point.costUsd))
                    .foregroundStyle(Palette.ink.opacity(0.85))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: Metrics.turnChartHeight)
            .accessibilityLabel("Cost per turn")
            .accessibilityValue(summary)
        }
        .padding(.horizontal, Space.lg)
    }

    /// The plain-text twin of the chart for VoiceOver.
    private var summary: String {
        let total = points.reduce(0) { $0 + $1.costUsd }
        let turns = points.enumerated().map { index, point in
            "turn \(index + 1): \(ClaudeContextSheet.cost(point.costUsd))"
        }.formatted()
        return "\(ClaudeContextSheet.cost(total)) over \(points.count) turns: \(turns)"
    }
}
#endif
