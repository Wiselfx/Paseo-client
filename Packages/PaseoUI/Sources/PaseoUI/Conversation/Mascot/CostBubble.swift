#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The session-cost bubble the crab's long press opens: the cost, and the token total when the
/// provider reports one. `MascotCrab` places it and handles the dismissal.
struct CostBubble: View {
    let usage: ContextUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Session cost")
                .font(.paseo(.caption2))
                .foregroundStyle(Palette.secondaryInk)
            if let cost = usage.totalCostUsd {
                Text(ClaudeContextSheet.cost(cost))
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
            if let tokens = tokenTotal {
                Text("\(PaseoFormat.compactCount(tokens)) tokens")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Palette.cardBorder, lineWidth: 0.5)
        }
        // The values are part of the spoken label: a fixed label would hide the cost from VoiceOver.
        .accessibilityElement(children: .combine)
    }

    private var tokenTotal: Int? {
        switch (usage.inputTokens, usage.outputTokens) {
        case let (i?, o?): i + o
        case let (i?, nil): i
        case let (nil, o?): o
        case (nil, nil): nil
        }
    }
}
#endif
