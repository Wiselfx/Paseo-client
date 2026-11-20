#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The sidebar footer's usage block, in its own view (H4 §2, R-1).
///
/// It reads the usage store — the narrow `@Observable` child — and nothing else, so a load, a
/// failure or a phase change re-evaluates this block and never the sidebar's page. While the
/// toggle is off it reads no store state at all, so it costs nothing in the common case.
///
/// The block is never empty while the toggle is on: one line of meters, or one line of state.
/// Both are single `.caption` rows at `SidebarMetrics.usageLineHeight`, so the footer keeps its
/// height when the first load lands; the only growth allowed is one meter line becoming several,
/// and that is animated with `Motion.disclosure`.
///
/// Every number and word on a meter row comes from `UsageModel.display(window:as:)`
/// (Upstream: `packages/app/src/usage/window-bar.tsx:44-60`, `model.ts:7-19`): the drawn text, the
/// reset wording and the row's accessible label are read from that one value, so they cannot
/// disagree. Upstream's own copy, not ours (en.ts:2223-2292).
struct SidebarUsageFooter: View {
    let hostUsage: HostUsageStore
    /// Settings → Sidebar's toggle, passed as a value: the block hides itself, the page does not
    /// rebuild around it.
    let showInSidebar: Bool
    /// The page's route to the usage sheet (the block presents nothing of its own).
    let onOpenUsage: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if showInSidebar {
            // Built once per body, and only while the block is on screen.
            let lines = Self.lines(for: hostUsage.reports, now: now)
            VStack(spacing: 4) {
                if lines.isEmpty {
                    statusLine
                } else {
                    ForEach(lines) { line in
                        meterLine(line, among: lines)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            // One meter line becoming several is the only growth this block allows, and it is
            // animated. Appearing and disappearing (the toggle) happens behind the Settings
            // sheet, so it needs no curve of its own (H4 §2).
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion), value: lines.count)
        }
    }

    /// One clock for the whole block: a countdown is read once per body, not once per row.
    private var now: Date { Date() }

    // MARK: One meter

    /// A meter the footer can draw: a provider's summary window, with every string the row shows.
    struct Line: Identifiable {
        let id: String
        let source: String
        /// `UsageModel.display` for the window: label, percent, wording, tone.
        let display: UsageWindowDisplay
    }

    /// A report's summary windows (or its first window) that have a figure to draw. A window the
    /// host reports with only `remainingPct` still has one: `UsageModel.usedPercent` derives it
    /// (model.ts:7-11) and `displayPercent` reads that one function.
    static func lines(for reports: [UsageReportEntry], now: Date) -> [Line] {
        reports.flatMap { report -> [Line] in
            guard case .available(let available) = report.report else { return [] }
            return summaryWindows(available).compactMap { window in
                let display = UsageModel.display(window, as: .used, now: now)
                guard display.percent != nil else { return nil }
                return Line(
                    id: "\(report.sourceId).\(window.id)",
                    source: report.sourceLabel,
                    display: display)
            }
        }
    }

    private static func summaryWindows(_ available: AvailableUsageReport) -> [ProviderUsageWindow] {
        let flagged = available.windows.filter { $0.summary == true }
        if flagged.isEmpty { return Array(available.windows.prefix(1)) }
        return Array(flagged.prefix(2))
    }

    private func meterLine(_ line: Line, among lines: [Line]) -> some View {
        Button {
            onOpenUsage()
        } label: {
            HStack(spacing: 8) {
                // The label column is as wide as the widest label of the block, so every bar
                // starts at the same x: "Session" and "Weekly" no longer move their bars.
                ZStack(alignment: .leading) {
                    ForEach(lines) { other in
                        Text(labelText(other)).hidden()
                    }
                    Text(labelText(line))
                }
                .font(.paseo(.caption))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                // One size for every row of every surface: a bar is never wider or taller here
                // than on the row above.
                ClaudeUsageBar(percent: line.display.percent ?? 0)
                    .frame(width: SidebarMetrics.usageMeterWidth, alignment: .leading)
                Text(trailing(line.display))
                    .monospacedDigit()
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(
                maxWidth: .infinity, minHeight: SidebarMetrics.usageLineHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(line))
        .accessibilityIdentifier("sidebar.usage.\(line.id)")
    }

    private func labelText(_ line: Line) -> String { "\(line.source) · \(line.display.label)" }

    /// The compact visible text, "21% · resets 3h": the sidebar line is one short row, so it
    /// drops "used" and "in" and keeps the countdown's first unit. The numbers are the same ones
    /// the spoken label reads in full (`fullText`).
    private func trailing(_ display: UsageWindowDisplay) -> String {
        let value = display.value.replacing(" used", with: "")
        guard let countdown = display.countdown else { return value }
        if display.isAtRisk { return "\(value) · \(countdown)" }
        let words = countdown.replacing("resets in ", with: "resets ")
            .split(separator: " ")
        let short = countdown.hasPrefix("resets in ") ? words.prefix(2).joined(separator: " ") : countdown
        return "\(value) · \(short)"
    }

    /// The same figures in full, in upstream's words: "21% used · resets in 3h 12m".
    private func fullText(_ display: UsageWindowDisplay) -> String {
        guard let countdown = display.countdown else { return display.value }
        return "\(display.value) · \(countdown)"
    }

    /// The row's spoken label is the row's own strings: nothing is computed a second time.
    private func accessibilityLabel(_ line: Line) -> String {
        "\(line.source), \(line.display.label), \(fullText(line.display))"
    }

    // MARK: One line of state

    /// What the block shows when there is no meter to draw. `retries` separates "ask the host
    /// again" (the user's own tap, so a forced refresh) from "open the sheet, which explains".
    private enum Status {
        case loading
        case message(String, retries: Bool)
    }

    private var status: Status {
        guard hostUsage.isSupported else {
            return .message(HostUsageStore.unsupportedMessage, retries: false)
        }
        switch hostUsage.phase {
        case .idle, .loading:
            // Upstream `providerUsage.loading` (en.ts:2248).
            return .loading
        case .ready:
            // Upstream `providerUsage.empty` (en.ts:2251): the host answered, and no account had a
            // quota window to draw.
            return .message("No usage data", retries: false)
        case .failed(let message):
            return .message(message, retries: true)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .loading:
            caption("Loading usage...")
        case .message(let text, let retries):
            Button {
                if retries {
                    Task { _ = await hostUsage.load(forceRefresh: true) }
                } else {
                    onOpenUsage()
                }
            } label: {
                caption(text)
            }
            .buttonStyle(.plain)
            .accessibilityHint(retries ? "Tries again" : "Opens usage")
            .accessibilityIdentifier("sidebar.usage.status")
        }
    }

    /// The status row: the same `.caption` font and the same `minHeight` as a meter row, so the
    /// two are interchangeable without a height change.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.paseo(.caption))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .frame(
                maxWidth: .infinity, minHeight: SidebarMetrics.usageLineHeight, alignment: .leading
            )
            .contentShape(.rect)
    }
}
#endif
