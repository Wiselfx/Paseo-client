#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Every account the host reports usage for, with each window, balance and detail the host
/// knows. Calm secondary text for problems; pull to refresh re-asks the host (`forceRefresh`).
struct ClaudeUsageReportsSheet: View {
    let session: HostSession

    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Usage", close: { dismiss() })
            Group {
                if session.hostUsage.reports.isEmpty {
                    emptyState
                } else {
                    List {
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
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
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
            VStack(spacing: 12) {
                ProgressView().controlSize(.small).tint(ClaudePalette.ink)
                Text("Loading usage…")
                    .font(.system(size: 14))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Usage isn't available right now.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .ready:
            Text("The host reports no usage sources for this device.")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failure(let message):
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(ClaudePalette.panel, in: .rect(cornerRadius: 20))
    }

    private func usageCardHeader(_ report: UsageReportEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(report.sourceLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                if let account = report.accountLabel {
                    Text(account)
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.captionInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if case .available(let available) = report.report, let plan = available.planLabel {
                    Text(plan)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ClaudePalette.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(ClaudePalette.chip, in: .capsule)
                }
            }
            Text("Updated \(Self.relative(report.fetchedAt))")
                .font(.system(size: 11))
                .foregroundStyle(ClaudePalette.captionInk)
        }
    }

    // MARK: Window row

    private func windowRow(_ window: ProviderUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 8)
                Text(Self.percent(window.usedPct))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(window.usedPct == nil ? ClaudePalette.secondary : ClaudePalette.ink)
                Text(ClaudeUsageResets.short(afterISO: window.resetsAt) ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(ClaudePalette.secondary)
            }
            ClaudeUsageBar(percent: window.usedPct ?? 0, width: 240)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Small pieces

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
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
        return "\(Int(value.rounded()))% used"
    }

    static func compact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
#endif
