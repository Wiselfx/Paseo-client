import Foundation
import PaseoProtocol

/// Whether percentages read as the share used or the share left.
/// Upstream: packages/app/src/usage/preferences.ts:5-6 (`UsageDisplayAs`).
public enum UsageDisplayAs: String, Sendable, Hashable, CaseIterable, Codable {
    case used
    case remaining
}

/// What one window row shows: every string the row and its accessible label are built from, read
/// once from the same numbers so the two can never disagree.
///
/// Upstream has the same shape: `displayPercent` computes the share once, the text and the meter
/// both take it (window-bar.tsx:44-70), and `usageWindowRowLabel` derives the row's spoken label
/// from that same value (model.ts:26-33).
public struct UsageWindowDisplay: Sendable, Hashable {
    /// Upstream `formatProviderUsageLabel(window.id, window.label)`.
    public var label: String
    /// The share shown, under the user's used/remaining preference. nil when the host gave neither.
    public var percent: Double?
    /// "21% used" / "79% left", or "—" (window-bar.tsx:59-60).
    public var value: String
    /// The countdown, or the runs-out warning when the quota will not last (window-bar.tsx:47-55).
    public var countdown: String?
    /// The exact clock time of the reset, absent beside a runs-out warning.
    public var exactTime: String?
    /// The countdown is a runs-out warning rather than a reset (reset-line.tsx:15-23, 42-46).
    public var isAtRisk: Bool
    /// The source's own tone, else one derived from the used share (tone.ts:5-12).
    public var tone: ProviderUsageTone
}

/// What one balance row shows.
/// Upstream: packages/app/src/usage/balance-bar.tsx:16-87.
public struct UsageBalanceDisplay: Sendable, Hashable, Identifiable {
    /// The balance's wire id, so a list of them keeps its identity.
    public var id: String
    public var label: String
    /// "12 / 100", "$4.50 left", "—" (balance-bar.tsx:21-48).
    public var amountText: String
    /// The share used, for the row's meter; nil when the balance has no limit.
    public var usedPct: Double?
    public var countdown: String?
    public var exactTime: String?
    public var tone: ProviderUsageTone
}

/// A report's content as a card draws it: what the current outcome owns, and what a retained
/// report still shows from its last successful fetch.
/// Upstream: packages/app/src/usage/model.ts:208-239 (`resolveUsageReport`).
public struct UsageReportContent: Sendable, Hashable {
    public var windows: [ProviderUsageWindow]
    public var balances: [ProviderUsageBalance]
    public var details: [ProviderUsageDetail]
    public var planLabel: String?
    public var successfulAt: String?
    /// The content comes from an earlier successful fetch, not from this attempt.
    public var retained: Bool
    /// The problem sentences to print instead of, or above, the content.
    public var messages: [String]
}

/// The pure logic behind the usage surfaces: the share a window shows, its tone, its accessible
/// row label, a report's content, and how a report list merges with what is already on screen.
///
/// Upstream: `packages/app/src/usage/model.ts`, `tone.ts`, `balance-bar.tsx` and
/// `window-bar.tsx`. Nothing here reads a clock the caller did not pass, so it is testable.
public enum UsageModel {
    // MARK: - Percent (model.ts:7-19)

    /// The share used, from either field the host sends; null when it sent neither.
    public static func usedPercent(_ window: ProviderUsageWindow) -> Double? {
        if let used = window.usedPct { return used }
        if let remaining = window.remainingPct { return 100 - remaining }
        return nil
    }

    /// The share the user's preference shows (model.ts:13-19).
    public static func displayPercent(
        _ window: ProviderUsageWindow, as displayAs: UsageDisplayAs
    ) -> Double? {
        switch displayAs {
        case .used:
            return usedPercent(window)
        case .remaining:
            if let remaining = window.remainingPct { return remaining }
            guard let used = usedPercent(window) else { return nil }
            return 100 - used
        }
    }

    // MARK: - Tone (tone.ts:5-12)

    /// The source's tone for a window, or one derived from how much of it is used.
    public static func windowTone(_ window: ProviderUsageWindow) -> ProviderUsageTone {
        if let tone = window.tone { return tone }
        guard let used = usedPercent(window) else { return .default }
        if used > 90 { return .danger }
        if used >= 70 { return .warning }
        return .default
    }

    // MARK: - Window and balance rows

    /// One window row's strings. `retained` marks content from an earlier successful fetch, whose
    /// reset may have passed; `now` is the caller's clock (window-bar.tsx:44-60).
    public static func display(
        _ window: ProviderUsageWindow,
        as displayAs: UsageDisplayAs,
        retained: Bool = false,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> UsageWindowDisplay {
        let shown = displayPercent(window, as: displayAs)
        let isAtRisk = window.runsOutAt != nil && window.shortfallPct != nil
            && (!retained || runsOutIsAhead(window.runsOutAt, now: now))
        let countdown = isAtRisk
            ? UsageFormat.runsOutLabel(window.runsOutAt, now: now)
            : UsageFormat.resetLabel(window.resetsAt, retained: retained, now: now)
        // The exact time belongs to the reset; beside a runs-out warning it would read as the
        // moment the quota runs out (window-bar.tsx:55-57).
        let exactTime =
            isAtRisk ? nil : UsageFormat.resetTime(window.resetsAt, now: now, locale: locale,
                timeZone: timeZone)
        return UsageWindowDisplay(
            label: UsageFormat.providerUsageLabel(id: window.id, label: window.label),
            percent: shown,
            value: shown.map { UsageFormat.displayPercent($0, as: displayAs) }
                ?? UsageFormat.unknownValue,
            countdown: countdown,
            exactTime: exactTime,
            isAtRisk: isAtRisk,
            tone: windowTone(window))
    }

    private static func runsOutIsAhead(_ iso: String?, now: Date) -> Bool {
        guard let iso, let target = PaseoDate.parse(iso) else { return false }
        return target > now
    }

    /// One balance row's strings (balance-bar.tsx:21-48).
    public static func display(
        _ balance: ProviderUsageBalance,
        retained: Bool = false,
        now: Date = .now,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> UsageBalanceDisplay {
        UsageBalanceDisplay(
            id: balance.id,
            label: UsageFormat.providerUsageLabel(id: balance.id, label: balance.label),
            amountText: amountText(balance),
            usedPct: usedShare(balance),
            countdown: UsageFormat.resetLabel(balance.resetsAt, retained: retained, now: now),
            exactTime: UsageFormat.resetTime(
                balance.resetsAt, now: now, locale: locale, timeZone: timeZone),
            tone: balance.tone ?? .default)
    }

    /// "12 / 100" against a limit (deriving the used amount from the remainder), else the amount
    /// left, else what was used, else "—" (balance-bar.tsx:30-47).
    static func amountText(_ balance: ProviderUsageBalance) -> String {
        let format = { (value: Double) in UsageFormat.amount(value, unit: balance.unit) }
        if let limit = balance.limit, limit > 0 {
            let usedAmount = balance.used ?? balance.remaining.map { limit - $0 }
            let usedText = usedAmount.map(format) ?? UsageFormat.unknownValue
            return "\(usedText) / \(format(limit))"
        }
        if let remaining = balance.remaining {
            return UsageFormat.remaining(format(remaining))
        }
        if let used = balance.used { return format(used) }
        return UsageFormat.unknownValue
    }

    /// The meter's share of a balance, only while there is a limit to measure against.
    static func usedShare(_ balance: ProviderUsageBalance) -> Double? {
        guard let limit = balance.limit, limit > 0 else { return nil }
        let usedAmount = balance.used ?? balance.remaining.map { limit - $0 }
        return usedAmount.map { $0 / limit * 100 }
    }

    // MARK: - Row labels (model.ts:21-33)

    /// A window row's accessible label: what pinning it pins, then what the row shows.
    /// "Pin Claude Session, 31% used · resets in 2h".
    public static func windowRowLabel(
        pinLabel: String, value: String, trailing: String?
    ) -> String {
        let summary = trailing.map { "\(value) · \($0)" } ?? value
        return "\(pinLabel), \(summary)"
    }

    // MARK: - A report's content (model.ts:208-239)

    /// What a card shows for one report. The current outcome owns the messages; only a successful
    /// fetch owns values and freshness.
    public static func resolve(_ entry: UsageReportEntry, now: Date = .now)
        -> UsageReportContent
    {
        let available = isAvailable(entry.report)
        // COMPAT(usageLastSuccessful): an older daemon cannot provide history; a failed attempt is
        // never a successful update (model.ts:211-214).
        let snapshot = available ? nil : entry.lastSuccessful
        let content: AvailableUsageReport?
        if case .available(let report) = entry.report {
            content = report
        } else {
            content = snapshot?.report
        }
        var messages: [String] = []
        if !available {
            if let loginErrors = entry.loginErrors, !loginErrors.isEmpty {
                // COMPAT(usageLoginErrors): one sentence per harness that could not sign in
                // (model.ts:214-225).
                messages = loginErrors.map { login in
                    "\(login.harness): \(problemText(login.report, now: now))"
                }
            } else {
                messages = [problemText(entry.report, now: now)]
            }
        }
        return UsageReportContent(
            windows: content?.windows ?? [],
            balances: content?.balances ?? [],
            details: content?.details ?? [],
            planLabel: content?.planLabel,
            // COMPAT(usageSuccessfulAt): older daemons expose only the attempt time, and never for
            // a failure (model.ts:231-235).
            successfulAt: available ? (entry.successfulAt ?? entry.fetchedAt) : snapshot?.fetchedAt,
            retained: snapshot != nil,
            messages: messages)
    }

    private static func isAvailable(_ report: UsageReport) -> Bool {
        if case .available = report { return true }
        return false
    }

    private static func problemText(_ report: UsageReport, now: Date) -> String {
        switch report {
        case .failure(let error): return error
        case .unavailable(let problem): return UsageFormat.problem(problem, now: now)
        case .available: return ""
        }
    }

    // MARK: - Merging a report list (model.ts:35-99)

    /// A report list with one report swapped for its refreshed copy, in place. nil means the
    /// daemon no longer knows the id, so the report leaves the list (model.ts:47-58).
    public static func replaceReport(
        _ reports: [UsageReportEntry], reportId: String, refreshed: UsageReportEntry?
    ) -> [UsageReportEntry] {
        guard let refreshed else { return reports.filter { $0.id != reportId } }
        return reports.map { $0.id == reportId ? refreshed : $0 }
    }

    /// A report list with one streamed report in place of its previous copy, or appended if new.
    /// A copy fetched after the streamed one stays (model.ts:64-78).
    public static func upsertReport(
        _ reports: [UsageReportEntry]?, _ report: UsageReportEntry
    ) -> [UsageReportEntry] {
        guard var shown = reports, shown.contains(where: { $0.id == report.id }) else {
            return (reports ?? []) + [report]
        }
        for index in shown.indices where shown[index].id == report.id {
            shown[index] = laterFetched(shown[index], report)
        }
        return shown
    }

    /// Keep displayed reports in place: the finished list is in fetch-completion order, which can
    /// change on every refresh. Drop missing reports, append new ones, and keep newer copies
    /// (model.ts:80-99).
    public static func settleReports(
        shown: [UsageReportEntry]?, finished: [UsageReportEntry]
    ) -> [UsageReportEntry] {
        var remaining: [String: UsageReportEntry] = [:]
        for report in finished { remaining[report.id] = report }
        var settled: [UsageReportEntry] = []
        for report in shown ?? [] {
            guard let arriving = remaining.removeValue(forKey: report.id) else { continue }
            settled.append(laterFetched(report, arriving))
        }
        // Dictionary order is not stable; the arrival order of what is left is.
        let appended = finished.compactMap { remaining[$0.id] }
        return settled + appended
    }

    /// The later-fetched of two copies of one report (model.ts:61-66).
    private static func laterFetched(
        _ shown: UsageReportEntry, _ arriving: UsageReportEntry
    ) -> UsageReportEntry {
        let shownAt = PaseoDate.parse(shown.fetchedAt)
        let arrivingAt = PaseoDate.parse(arriving.fetchedAt)
        guard let shownAt, let arrivingAt else { return arriving }
        return shownAt > arrivingAt ? shown : arriving
    }
}
