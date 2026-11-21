#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The horizontal bar list: each model row carries a proportional bar under the
/// figures (neutral ink — the per-turn output chart owns the one accent).
/// The bar is decorative; the numbers carry the meaning for VoiceOver.
struct CostByModelSection: View {
    let usage: ContextUsage

    var body: some View {
        if let costByModel = usage.costByModel, !costByModel.isEmpty {
            let peak = max(costByModel.map(\.costUsd).max() ?? 0, 0.0001)
            VStack(alignment: .leading, spacing: Space.sm) {
                ContextSectionLabel(title: "Cost by model")
                RowGroup {
                    ForEach(costByModel.enumerated(), id: \.element.key) { index, entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: Space.md) {
                                Text(ClaudeContextSheet.modelName(entry.key))
                                    .font(.paseo(.code))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: Space.sm)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(ClaudeContextSheet.cost(entry.costUsd, fractionDigits: 4))
                                        .monospacedDigit()
                                        .font(.paseo(.callout, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Text("\(ClaudeContextSheet.tokenCount(entry.tokens)) tokens")
                                        .monospacedDigit()
                                        .font(.paseo(.caption2))
                                        .foregroundStyle(Palette.secondaryInk)
                                }
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Palette.chip)
                                        .frame(height: Metrics.costBarThickness)
                                    Capsule()
                                        .fill(Palette.ink.opacity(0.45))
                                        .frame(
                                            width: proxy.size.width
                                                * max(0, CGFloat(entry.costUsd / peak)),
                                            height: Metrics.costBarThickness)
                                }
                            }
                            .accessibilityHidden(true)
                            .frame(height: Metrics.costBarThickness)
                        }
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        if index < costByModel.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }
}
#endif
