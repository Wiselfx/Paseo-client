#if canImport(UIKit)
import Charts
import PaseoStore
import SwiftUI

/// Usage, in two layers: a calm overview on top (DSH home figures, rolled up from the agent
/// list's `lastUsage` — see `UsageOverviewBuilder`), then every account the host reports
/// quota windows for, with pull to refresh re-asking the host (`forceRefresh`).
struct ClaudeUsageReportsSheet: View {
    let session: HostSession

    private var overview: UsageOverview {
        UsageOverviewBuilder.compute(agents: session.agents)
    }

    var body: some View {
        SheetScaffold("Usage", detents: .large) {
            Group {
                if session.hostUsage.reports.isEmpty && overview.sessions == 0 {
                    emptyState
                } else {
                    List {
                        overviewCard
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        ForEach(session.hostUsage.reports) { report in
                            usageCard(report)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await refresh() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .task {
            if case .idle = session.hostUsage.phase {
                _ = await session.hostUsage.load(forceRefresh: false)
            }
        }
    }

    // MARK: Empty / loading states

    @ViewBuilder private var emptyState: some View {
        switch session.hostUsage.phase {
        case .loading, .idle:
            LoadingState("Loading usage…")
        case .failed(let message):
            EmptyState(
                title: "Usage isn't available right now.",
                message: message
            )
            .padding(24)
        case .ready:
            EmptyState(title: "The host reports no usage sources for this device.")
        }
    }

    // MARK: Overview (DSH home figures)

    /// The six stat cells, the 14-day token chart and the per-model split, from the agent
    /// list's `lastUsage` (DSH's session-list fallback). A figure no source can answer is a
    /// dash, not a zero.
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Overview")
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.ink)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statCell(label: "Sessions", value: "\(overview.sessions)")
                statCell(label: "Messages", value: "—")
                statCell(label: "Total tokens", value: Self.compactTokens(overview.tokens))
                statCell(label: "Active days", value: "\(overview.activeDays)")
                statCell(label: "Peak hour", value: overview.peakHourLabel ?? "—")
                statCell(label: "Favorite model", value: overview.favoriteModel ?? "—")
            }
            if overview.tokens > 0 {
                Text("Tokens by day")
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                Chart(overview.days, id: \.date) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Tokens", day.tokens))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month())
                } }
                .frame(height: 110)
                .accessibilityLabel("Tokens by day, last 14 days")
                .accessibilityValue(Self.compactTokens(overview.tokens) + " tokens total")
                if !overview.models.isEmpty {
                    Text("Tokens by model")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    Chart(overview.models.prefix(6), id: \.model) { model in
                        BarMark(
                            x: .value("Model", model.model),
                            y: .value("Tokens", model.tokens))
                            .foregroundStyle(Palette.ink.opacity(0.85))
                    }
                    .frame(height: 110)
                    .accessibilityLabel("Tokens by model")
                    .accessibilityValue(Self.compactTokens(overview.tokens) + " tokens total")
                }
                if let fun = UsageBooks.funLine(forTokens: overview.tokens) {
                    Text(fun)
                        .font(.paseo(.footnote))
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                Text("No usage yet.")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(16)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.paseo(.caption2))
                .foregroundStyle(Palette.secondaryInk)
            Text(value)
                .font(.paseo(.headline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    // MARK: A report

    private func usageCard(_ report: UsageReportEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            usageCardHeader(report)
            switch report.report {
            case .available(let available):
                ForEach(available.windows) { window in
                    windowRow(window)
                }
                ForEach(available.balances ?? []) { balance in
                    infoRow(balance.label, value: balanceValue(balance))
                }
                ForEach(available.details ?? []) { detail in
                    infoRow(detail.label, value: detail.value)
                }
            case .unavailable(let problem):
                Text(problemText(problem))
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let message):
                Text(message)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.lg))
    }

    private func usageCardHeader(_ report: UsageReportEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(report.sourceLabel)
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if let account = report.accountLabel {
                    Text(account)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.captionInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if case .available(let available) = report.report, let plan = available.planLabel {
                    Text(plan)
                        .font(.paseo(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Palette.chip, in: .capsule)
                }
            }
            Text("Updated \(Self.relative(report.fetchedAt))")
                .font(.paseo(.caption2))
                .foregroundStyle(Palette.captionInk)
        }
    }

    // MARK: Window row

    private func windowRow(_ window: ProviderUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(Self.percent(window.usedPct))
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(window.usedPct == nil ? Palette.secondaryInk : Palette.ink)
                Text(ClaudeUsageResets.short(afterISO: window.resetsAt) ?? "")
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
            }
            ClaudeUsageBar(percent: window.usedPct ?? 0, width: 240)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Small pieces

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: 8)
            Text(value)
                .font(.paseo(.footnote, weight: .medium))
                .foregroundStyle(Palette.ink)
        }
    }

    private func balanceValue(_ balance: ProviderUsageBalance) -> String {
        let amount: (Double) -> String = { value in
            switch balance.unit {
            case .usd: "$\(Self.compact(value))"
            case .credits: Self.compact(value) + " credits"
            case .requests: Self.compact(value) + " requests"
            case .tokens: Self.compact(value) + " tokens"
            case .unknown: Self.compact(value)
            }
        }
        switch (balance.used, balance.remaining, balance.limit) {
        case (let used?, let remaining?, _): return "\(amount(used)) used · \(amount(remaining)) left"
        case (let used?, nil, let limit?): return "\(amount(used)) of \(amount(limit))"
        case (nil, let remaining?, _): return "\(amount(remaining)) left"
        case (_, _, let limit?): return "of \(amount(limit))"
        default: return "—"
        }
    }

    private func problemText(_ problem: UsageProblem) -> String {
        switch problem {
        case .expired(let expiresAt, _):
            "The host's credentials expired (as of \(Self.relative(expiresAt)))."
        case .rejected(let status, _):
            "The host rejected the credentials (status \(status))."
        case .noQuota(let detail):
            "Not available: \(detail)"
        case .unknown:
            "Usage is temporarily unavailable for this source."
        }
    }

    private func refresh() async {
        _ = await session.hostUsage.load(forceRefresh: true)
    }

    static func relative(_ iso: String) -> String {
        guard let date = PaseoDate.parse(iso) else { return "unknown time" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(PaseoFormat.percent(value)) used"
    }

    static func compact(_ value: Double) -> String {
        PaseoFormat.compact(value)
    }
}
#endif
