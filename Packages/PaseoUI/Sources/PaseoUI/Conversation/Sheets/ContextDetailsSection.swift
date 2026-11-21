#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The "Session" group: only the figures the host reports, each as a value row.
struct ContextDetailsSection: View {
    let usage: ContextUsage

    var body: some View {
        let details = makeDetails()
        if !details.isEmpty {
            VStack(alignment: .leading, spacing: Space.sm) {
                ContextSectionLabel(title: "Session")
                RowGroup {
                    ForEach(details.enumerated(), id: \.element.id) { index, detail in
                        ContextValueRow(label: detail.label, value: detail.value)
                        if index < details.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }

    private func makeDetails() -> [ContextDetail] {
        var details: [ContextDetail] = []
        if let used = usage.usedTokens, let max = usage.maxTokens {
            details.append(
                ContextDetail(
                    label: "Used",
                    value: "\(ClaudeContextSheet.tokenCount(used)) / \(ClaudeContextSheet.tokenCount(max)) tokens"))
        } else if let used = usage.usedTokens {
            details.append(
                ContextDetail(label: "Used", value: "\(ClaudeContextSheet.tokenCount(used)) tokens"))
        } else if let max = usage.maxTokens {
            details.append(
                ContextDetail(label: "Window", value: "\(ClaudeContextSheet.tokenCount(max)) tokens"))
        }
        if let input = usage.inputTokens {
            details.append(
                ContextDetail(label: "Input tokens", value: ClaudeContextSheet.tokenCount(input)))
        }
        if let output = usage.outputTokens {
            details.append(
                ContextDetail(label: "Output tokens", value: ClaudeContextSheet.tokenCount(output)))
        }
        if let hit = usage.sessionCacheHitRatePct {
            details.append(
                ContextDetail(label: "Cache hit rate", value: ClaudeContextSheet.percentValue(hit)))
        }
        if let hit = usage.lastTurnCacheHitRatePct {
            details.append(
                ContextDetail(
                    label: "Last turn cache hit", value: ClaudeContextSheet.percentValue(hit)))
        }
        if let cost = usage.totalCostUsd {
            details.append(
                ContextDetail(label: "Session cost", value: ClaudeContextSheet.cost(cost)))
        }
        if let waste = usage.cacheWaste {
            details.append(
                ContextDetail(
                    label: "Cache waste",
                    value: "\(ClaudeContextSheet.tokenCount(waste.tokens)) tokens · \(ClaudeContextSheet.cost(waste.costUsd, fractionDigits: 4))"))
        }
        return details
    }
}
#endif
