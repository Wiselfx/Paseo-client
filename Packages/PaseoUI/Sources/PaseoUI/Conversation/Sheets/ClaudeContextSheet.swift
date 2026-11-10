#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The composer's context-window details, fed by `ConversationStore.contextUsage` — the
/// host's snapshot values and the live window fields from the stream. No placeholder numbers:
/// rows only appear when the host reports them, and agents with no usage get a calm line.
struct ClaudeContextSheet: View {
    let store: ConversationStore

    var body: some View {
        SheetScaffold("Context", detents: .mediumLarge) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let usage = store.contextUsage, let percent = usage.percentUsed {
                        meterRow(usage: usage, percent: percent)
                        detailsSection(usage: usage)
                        costByModelSection(usage: usage)
                    } else {
                        EmptyState(
                            title: "This agent's host does not report context usage yet."
                        )
                        .padding(.horizontal, Space.lg)
                        .padding(.top, Space.xl)
                    }
                }
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Header row

    private func meterRow(usage: ContextUsage, percent: Double) -> some View {
        HStack(spacing: 18) {
            ClaudeMeterRing(percent: percent, size: 64, lineWidth: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(PaseoFormat.percent(percent)) used")
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                if let max = usage.maxTokens {
                    Text("of \(Self.tokenCount(max)) tokens")
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xl)
    }

    // MARK: Detail rows

    @ViewBuilder private func detailsSection(usage: ContextUsage) -> some View {
        let rows = detailRows(usage: usage)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Session")
                RowGroup {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        row
                        if index < rows.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }

    private func detailRows(usage: ContextUsage) -> [AnyView] {
        var rows: [AnyView] = []
        if let used = usage.usedTokens, let max = usage.maxTokens {
            rows.append(AnyView(
                valueRow("Used", value: "\(Self.tokenCount(used)) / \(Self.tokenCount(max)) tokens")))
        } else if let used = usage.usedTokens {
            rows.append(AnyView(valueRow("Used", value: "\(Self.tokenCount(used)) tokens")))
        } else if let max = usage.maxTokens {
            rows.append(AnyView(valueRow("Window", value: "\(Self.tokenCount(max)) tokens")))
        }
        if let input = usage.inputTokens {
            rows.append(AnyView(valueRow("Input tokens", value: Self.tokenCount(input))))
        }
        if let output = usage.outputTokens {
            rows.append(AnyView(valueRow("Output tokens", value: Self.tokenCount(output))))
        }
        if let hit = usage.sessionCacheHitRatePct {
            rows.append(AnyView(valueRow("Cache hit rate", value: Self.percentValue(hit))))
        }
        if let hit = usage.lastTurnCacheHitRatePct {
            rows.append(AnyView(valueRow("Last turn cache hit", value: Self.percentValue(hit))))
        }
        if let cost = usage.totalCostUsd {
            rows.append(AnyView(valueRow("Session cost", value: Self.cost(cost))))
        }
        if let waste = usage.cacheWaste {
            rows.append(AnyView(
                valueRow(
                    "Cache waste",
                    value: "\(Self.tokenCount(waste.tokens)) tokens · \(Self.cost(waste.costUsd, fractionDigits: 4))")))
        }
        return rows
    }

    // MARK: Cost by model

    @ViewBuilder private func costByModelSection(usage: ContextUsage) -> some View {
        if let costByModel = usage.costByModel, !costByModel.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Cost by model")
                RowGroup {
                    ForEach(Array(costByModel.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 12) {
                            Text(Self.modelName(entry.key))
                                .font(.paseo(.code))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Self.cost(entry.costUsd, fractionDigits: 4))
                                    .font(.paseo(.callout, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Text("\(Self.tokenCount(entry.tokens)) tokens")
                                    .font(.paseo(.caption2))
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        if index < costByModel.count - 1 { RowDivider() }
                    }
                }
            }
        }
    }

    // MARK: Shared bits

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.footnote, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, -4)
    }

    private func valueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.paseo(.body))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    static func tokenCount(_ value: Int) -> String {
        PaseoFormat.integer(value)
    }

    static func percentValue(_ value: Double) -> String {
        PaseoFormat.percent(value)
    }

    static func cost(_ value: Double, fractionDigits: Int = 2) -> String {
        String(format: "$%.\(fractionDigits)f", value)
    }

    static func modelName(_ key: String) -> String {
        key.isEmpty ? "model" : key
    }
}
#endif
