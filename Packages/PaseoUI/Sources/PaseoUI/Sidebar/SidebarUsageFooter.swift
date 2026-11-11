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
            let lines = Self.lines(for: hostUsage.reports)
            VStack(spacing: 4) {
                if lines.isEmpty {
                    statusLine
                } else {
                    ForEach(lines) { line in
                        meterLine(line)
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

    // MARK: One meter

    /// A meter the footer can draw: a provider's summary window with its percentage and reset.
    struct Line: Identifiable {
        let id: String
        let source: String
        let label: String
        let used: Double
        let resetsAt: String?
    }

    /// A report's summary windows (or its first window), only when the host gave a percentage.
    static func lines(for reports: [UsageReportEntry]) -> [Line] {
        reports.flatMap { report -> [Line] in
            guard case .available(let available) = report.report else { return [] }
            return summaryWindows(available).compactMap { window in
                guard let used = window.usedPct else { return nil }
                return Line(
                    id: "\(report.sourceId).\(window.id)",
                    source: report.sourceLabel,
                    label: window.label,
                    used: used,
                    resetsAt: window.resetsAt)
            }
        }
    }

    private static func summaryWindows(_ available: AvailableUsageReport) -> [ProviderUsageWindow] {
        let flagged = available.windows.filter { $0.summary == true }
        if flagged.isEmpty { return Array(available.windows.prefix(1)) }
        return Array(flagged.prefix(2))
    }

    private func meterLine(_ line: Line) -> some View {
        let resets = ClaudeUsageResets.short(afterISO: line.resetsAt)
        let percent = Int(min(max(line.used, 0), 100).rounded())
        return Button {
            onOpenUsage()
        } label: {
            HStack(spacing: 8) {
                Text("\(line.source) · \(line.label)")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                ClaudeUsageBar(percent: line.used, width: 44)
                Text(resets.map { "\(percent)% · \($0)" } ?? "\(percent)%")
                    .monospacedDigit()
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize()
            }
            .frame(
                maxWidth: .infinity, minHeight: SidebarMetrics.usageLineHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(line.source), \(line.label), \(percent) percent used"
                + (resets.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("sidebar.usage.\(line.id)")
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
            return .loading
        case .ready:
            // Upstream `providerUsage.empty` (en.ts:2249): the host answered, and no account had a
            // quota window to draw.
            return .message("No usage data", retries: false)
        case .failed(let message):
            return .message(message, retries: true)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .loading:
            caption("Loading usage…")
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
