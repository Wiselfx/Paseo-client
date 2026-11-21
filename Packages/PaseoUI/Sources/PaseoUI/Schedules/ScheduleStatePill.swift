#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Shared state pill and formatting helpers for the Schedules pages.
/// The pill a row shows; active/paused/finished/expired/target gone, in warn or wash tints.
struct ScheduleStatePill: View {
    let state: ScheduleState

    var body: some View {
        Text(label)
            .font(.paseo(.caption, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, Space.sm)
            .frame(minHeight: 18)
            .background(ink.opacity(0.16), in: .rect(cornerRadius: Radius.xs))
            .accessibilityLabel(label)
    }

    private var label: String {
        switch state {
        case .active: "Active"
        case .paused: "Paused"
        case .expired: "Expired"
        case .finished: "Finished"
        case .targetGone: "Target gone"
        case .unknown: "Unknown"
        }
    }

    private var ink: Color {
        switch state {
        case .active: Palette.successInk
        case .paused: Palette.warning
        case .expired, .finished, .unknown: Palette.secondaryInk
        case .targetGone: Palette.failureInk
        }
    }
}

/// An ISO-8601 instant ("2026-11-09T07:30:00Z") in the device's date and time style, or "—".
@MainActor func scheduleTimestamp(_ iso: String?) -> String {
    guard let iso, let date = PaseoDate.parse(iso) else { return "—" }
    return PaseoFormat.dateTime(date)
}

/// "in 3 hr.", "Tomorrow at 09:00" for a next-run caption; "Not scheduled" when missing. The
/// relative part comes from the system formatter, so units and plurals follow the locale.
@MainActor func scheduleNextRun(_ iso: String?) -> String {
    guard let iso, let date = PaseoDate.parse(iso) else { return "Not scheduled" }
    let seconds = date.timeIntervalSinceNow
    if seconds < 0 { return "Overdue" }
    if seconds < 86_400 { return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)) }
    let days = Int(seconds / 86_400)
    return days == 1
        ? "Tomorrow at \(PaseoFormat.time(date))"
        : "\(date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))) · \(PaseoFormat.dateTime(date))"
}

func scheduleDuration(_ start: String, _ end: String?) -> String {
    guard let startDate = PaseoDate.parse(start) else { return "—" }
    let endDate = end.flatMap(PaseoDate.parse) ?? .now
    let seconds = max(0, endDate.timeIntervalSince(startDate))
    if seconds < 1 { return "<1s" }
    return Duration.seconds(seconds.rounded(.down))
        .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
}

extension ScheduleCadence {
    /// The cadence line for the list: human words in the device time zone, never the raw expression.
    /// Views pass `@Environment(\.timeZone)` and compute it once per body, since each call runs the
    /// next-occurrence calendar math.
    func words(now: Date = .now, timeZone: TimeZone = .current) -> String {
        switch self {
        case .every(let everyMs): ScheduleWords.cadence(everyMs: everyMs)
        case .cron(let expression, let timezone):
            CronDescription.describe(expression: expression, scheduleTimeZone: timezone, now: now, deviceTimeZone: timeZone)
        case .unknown: CronDescription.custom
        }
    }

    /// The raw expression for the detail page only, when the cadence has no human words.
    func detailRawExpression(now: Date = .now, timeZone: TimeZone = .current) -> String? {
        switch self {
        case .every: nil
        case .cron(let expression, let timezone):
            CronDescription.isCustom(expression: expression, scheduleTimeZone: timezone, now: now, deviceTimeZone: timeZone) ? expression : nil
        case .unknown(let raw): raw
        }
    }

    /// The schedule's own time zone, shown in the detail page only.
    var scheduleTimeZone: String? {
        switch self {
        case .cron(_, let timezone): timezone?.isEmpty == false ? timezone : nil
        case .every, .unknown: nil
        }
    }

    /// The detail-page cadence line: the list words plus the schedule time zone, when present.
    func detailWords(now: Date = .now, timeZone: TimeZone = .current) -> String {
        let line = words(now: now, timeZone: timeZone)
        guard let scheduleTimeZone else { return line }
        return "\(line) · \(scheduleTimeZone)"
    }
}

extension ScheduleTarget {
    /// The stored new-agent config, when the target creates a fresh agent each run.
    var newAgentConfig: ScheduleNewAgentConfig? {
        if case .newAgent(let config) = self { return config }
        return nil
    }

    /// The agent id when the target prompts an existing agent (a heartbeat).
    var agentId: String? {
        switch self {
        case .agent(let agentId), .selfAgent(let agentId): agentId
        default: nil
        }
    }
}

#endif
