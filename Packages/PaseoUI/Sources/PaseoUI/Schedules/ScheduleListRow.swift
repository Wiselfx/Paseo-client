#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One row of the Schedules list: title and cadence, the state pill and the next run. It pushes
/// the detail page; the verbs live in its context menu and Delete also swipes. The page owns the
/// actions and passes them in, so the row only draws.
struct ScheduleListRow: View {
    let summary: ScheduleSummary
    let knownAgentIds: Set<String>?
    let now: Date
    let onSetPaused: (Bool) -> Void
    let onRunNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.timeZone) private var timeZone

    var body: some View {
        // The cadence words run the next-occurrence calendar math, so they are read once per body.
        let state = summary.state(now: now, knownAgentIds: knownAgentIds)
        let cadenceWords = summary.cadence.words(now: now, timeZone: timeZone)
        let caption = nextCaption(state)
        NavigationLink(value: ClaudeSchedulesView.Route.detail(summary.id)) {
            HStack(spacing: 0) {
                ListRow(title: title, subtitle: cadenceWords)
                VStack(alignment: .trailing, spacing: Space.xs) {
                    ScheduleStatePill(state: state)
                    Text(caption)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.captionInk)
                }
                .padding(.trailing, Space.lg)
            }
        }
        .panelRow()
        .accessibilityLabel("Schedule \(title)")
        .accessibilityValue("\(cadenceWords), \(caption)")
        .contextMenu {
            ScheduleRowMenu(
                summary: summary, onSetPaused: onSetPaused, onRunNow: onRunNow, onEdit: onEdit,
                onDelete: onDelete)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var title: String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(
            separator: "\n", maxSplits: 1, omittingEmptySubsequences: true
        ).first
        return firstLine.map(String.init) ?? "Untitled schedule"
    }

    private func nextCaption(_ state: ScheduleState) -> String {
        switch state {
        case .paused: return "Paused"
        case .expired, .finished: return "No upcoming run"
        default: return scheduleNextRun(summary.nextRunAt)
        }
    }
}
#endif
