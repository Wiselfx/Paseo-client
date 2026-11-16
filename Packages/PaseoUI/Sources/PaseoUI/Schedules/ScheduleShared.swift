#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Shared state pill and formatting helpers for the Schedules pages.
/// The pill a row shows; active/paused/finished/expired/target gone, in warn or wash tints.
struct ScheduleStatePill: View {
    let state: ScheduleState

    var body: some View {
        Text(label)
            .font(.paseo(.caption2, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 18)
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

/// "In 3h", "Tomorrow at 09:00" for a next-run caption; "Not scheduled" when missing.
@MainActor func scheduleNextRun(_ iso: String?) -> String {
    guard let iso, let date = PaseoDate.parse(iso) else { return "Not scheduled" }
    let seconds = date.timeIntervalSinceNow
    if seconds < 0 { return "Overdue" }
    if seconds < 3600 { return "In \(max(1, Int(seconds / 60))) min" }
    if seconds < 86_400 { return "In \(Int(seconds / 3600))h" }
    let days = Int(seconds / 86_400)
    return days == 1
        ? "Tomorrow at \(PaseoFormat.time(date))"
        : "In \(days) days · \(PaseoFormat.dateTime(date))"
}

func scheduleDuration(_ start: String, _ end: String?) -> String {
    guard let startDate = PaseoDate.parse(start) else { return "—" }
    let endDate = end.flatMap(PaseoDate.parse) ?? Date()
    let seconds = max(0, endDate.timeIntervalSince(startDate))
    if seconds < 1 { return "<1s" }
    if seconds < 60 { return "\(Int(seconds))s" }
    return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
}

extension ScheduleCadence {
    /// The cadence line for the list: human words in the device time zone, never the raw expression.
    var words: String {
        switch self {
        case .every(let everyMs): ScheduleWords.cadence(everyMs: everyMs)
        case .cron(let expression, let timezone):
            CronDescription.describe(expression: expression, scheduleTimeZone: timezone, now: Date(), deviceTimeZone: .current)
        case .unknown: CronDescription.custom
        }
    }

    /// The raw expression for the detail page only, when the cadence has no human words.
    var detailRawExpression: String? {
        switch self {
        case .every: nil
        case .cron(let expression, let timezone):
            CronDescription.isCustom(expression: expression, scheduleTimeZone: timezone, now: Date(), deviceTimeZone: .current) ? expression : nil
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
    var detailWords: String {
        guard let scheduleTimeZone else { return words }
        return "\(words) · \(scheduleTimeZone)"
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
