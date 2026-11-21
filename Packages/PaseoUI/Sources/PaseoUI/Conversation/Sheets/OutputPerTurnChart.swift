#if canImport(UIKit)
import Charts
import PaseoStore
import SwiftUI

/// One accent, no legend (one series): the dataviz rule is one accent total,
/// so the cost bars (`CostPerTurnChart`) stay neutral ink.
struct OutputPerTurnChart: View {
    let points: [TurnUsagePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Output per turn")
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
            Chart(Array(points.enumerated()), id: \.offset) { index, point in
                BarMark(
                    x: .value("Turn", index + 1),
                    y: .value("Output", point.outputTokens))
                    .foregroundStyle(Palette.accent)
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
                    AxisValueLabel(format: IntegerFormatStyle<Int>.number.notation(.compactName))
                }
            }
            .frame(height: Metrics.turnChartHeight)
            .accessibilityLabel("Output per turn")
            .accessibilityValue(summary)
        }
        .padding(.horizontal, Space.lg)
    }

    /// The plain-text twin of the chart for VoiceOver: totals plus the
    /// per-turn values the bars draw.
    private var summary: String {
        let total = points.reduce(0) { $0 + $1.outputTokens }
        let turns = points.enumerated().map { index, point in
            "turn \(index + 1): \(ClaudeContextSheet.tokenCount(point.outputTokens))"
        }.formatted()
        return "\(ClaudeContextSheet.tokenCount(total)) output tokens over \(points.count) turns: \(turns)"
    }
}
#endif
