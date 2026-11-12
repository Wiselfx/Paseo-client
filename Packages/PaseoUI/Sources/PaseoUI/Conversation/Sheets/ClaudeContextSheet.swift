#if canImport(UIKit)
import Charts
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
                    if let usage = store.contextUsage {
                        // A session with a window gets the meter; a session the provider reports
                        // without one keeps its figures and gets upstream's `contextWindow.noData`
                        // line where the percentage would be. Only a host that reports nothing at
                        // all falls through to the empty state (H3 §1).
                        if let percent = usage.percentUsed {
                            meterRow(usage: usage, percent: percent)
                        } else {
                            noWindowRow
                        }
                        detailsSection(usage: usage)
                        turnChartsSection(points: store.recentTurnUsage)
                        costByModelSection(usage: usage)
                    } else {
                        EmptyState(
                            title: "No context data",
                            message: "This agent's host does not report context usage yet."
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

    /// The same header slot as `meterRow`, with no window to draw: the composer's empty track, and
    /// upstream's wording (`contextWindow.noData`) where the percentage goes — its details sheet
    /// draws that line and keeps the session figures below it
    /// (`context-window-details.tsx:52-55`).
    private var noWindowRow: some View {
        HStack(spacing: 18) {
            ClaudeMeterRing(
                percent: 0, size: 64, lineWidth: 6, tint: Palette.secondaryInk, drawsArc: false)
            Text("No context data")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.xl)
    }

    private func meterRow(usage: ContextUsage, percent: Double) -> some View {
        HStack(spacing: 18) {
            ClaudeMeterRing(percent: percent, size: 64, lineWidth: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(PaseoFormat.percent(percent)) used")
                    .monospacedDigit()
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                if let max = usage.maxTokens {
                    Text("of \(Self.tokenCount(max)) tokens")
                        .monospacedDigit()
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

    // MARK: Per-turn charts (G13 C16)

    /// Output tokens and cost per turn, last 30, live turns only: the series starts
    /// where data starts, never with fake zeros for older turns. Both boxes are
    /// reserved from the first frame whether or not any turn has been observed.
    @ViewBuilder
    private func turnChartsSection(points: [TurnUsagePoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Usage per turn")
            if points.isEmpty {
                Text("Per-turn charts appear as turns complete.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Metrics.turnChartHeight)
                    .padding(.horizontal, Space.lg)
            } else {
                outputChart(points)
                costChart(points)
            }
        }
    }

    /// One accent, no legend (one series): the dataviz rule is one accent total,
    /// so the cost bars below stay neutral ink.
    private func outputChart(_ points: [TurnUsagePoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    AxisValueLabel(format: .number.notation(.compactName))
                }
            }
            .frame(height: Metrics.turnChartHeight)
            .accessibilityLabel("Output per turn")
            .accessibilityValue(outputSummary(points))
        }
        .padding(.horizontal, Space.lg)
    }

    private func costChart(_ points: [TurnUsagePoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .accessibilityValue(costSummary(points))
        }
        .padding(.horizontal, Space.lg)
    }

    /// The plain-text twin of the output chart for VoiceOver: totals plus the
    /// per-turn values the bars draw.
    private func outputSummary(_ points: [TurnUsagePoint]) -> String {
        let total = points.reduce(0) { $0 + $1.outputTokens }
        let turns = points.enumerated().map { index, point in
            "turn \(index + 1): \(Self.tokenCount(point.outputTokens))"
        }.joined(separator: ", ")
        return "\(Self.tokenCount(total)) output tokens over \(points.count) turns: \(turns)"
    }

    private func costSummary(_ points: [TurnUsagePoint]) -> String {
        let total = points.reduce(0) { $0 + $1.costUsd }
        let turns = points.enumerated().map { index, point in
            "turn \(index + 1): \(Self.cost(point.costUsd))"
        }.joined(separator: ", ")
        return "\(Self.cost(total)) over \(points.count) turns: \(turns)"
    }

    // MARK: Cost by model

    /// The horizontal bar list: each model row carries a proportional bar under the
    /// figures (neutral ink — the per-turn output chart owns the one accent).
    /// The bar is decorative; the numbers carry the meaning for VoiceOver.
    @ViewBuilder private func costByModelSection(usage: ContextUsage) -> some View {
        if let costByModel = usage.costByModel, !costByModel.isEmpty {
            let peak = max(costByModel.map(\.costUsd).max() ?? 0, 0.0001)
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Cost by model")
                RowGroup {
                    ForEach(Array(costByModel.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text(Self.modelName(entry.key))
                                    .font(.paseo(.code))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Self.cost(entry.costUsd, fractionDigits: 4))
                                        .monospacedDigit()
                                        .font(.paseo(.callout, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Text("\(Self.tokenCount(entry.tokens)) tokens")
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
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
                .monospacedDigit()
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        // `minHeight`, not `height`: a value row is a text container, and at the largest Dynamic
        // Type sizes a fixed 44 clips the value instead of growing the row.
        .frame(minHeight: 44)
    }

    static func tokenCount(_ value: Int) -> String {
        PaseoFormat.compactCount(value)
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
