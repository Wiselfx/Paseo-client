#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - Detail page

/// One schedule: its prompt, target, recent runs and the verbs for it. Pushed from the list, so
/// back is native; Delete pops back to the list when it succeeds.
struct ScheduleDetailPage: View {
    let session: HostSession
    let scheduleId: String

    @State private var hasInspected = false

    private var schedules: SchedulesStore { session.schedules }
    private var stored: StoredSchedule? {
        schedules.selected?.id == scheduleId ? schedules.selected : nil
    }
    private var summary: ScheduleSummary? { stored?.summary ?? schedules.schedule(id: scheduleId) }
    private var knownAgentIds: Set<String> { Set(session.agents.map(\.id)) }
    private var state: ScheduleState? {
        summary?.state(now: .now, knownAgentIds: knownAgentIds)
    }

    var body: some View {
        Group {
            if let summary {
                detail(summary)
            } else {
                LoadingState()
            }
        }
        .inlinePageTitle(summary.map(titleString) ?? "Schedule")
        .task {
            _ = await schedules.inspect(scheduleId)
            hasInspected = true
        }
        .refreshable { _ = await schedules.inspect(scheduleId) }
    }

    private func detail(_ summary: ScheduleSummary) -> some View {
        PageList {
            Section {
                ScheduleHero(summary: summary, title: titleString(summary), state: state)
                    .panelRow(Palette.background)
            }
            Section {
                Text(summary.prompt)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.lg)
                    .textSelection(.enabled)
                    .panelRow()
            } header: {
                Text("Prompt")
            }
            Section {
                ScheduleTargetRows(session: session, summary: summary)
            } header: {
                Text("Target")
            }
            Section {
                ScheduleRunsSection(runs: stored?.runs ?? [], hasInspected: hasInspected)
            } header: {
                Text("Recent runs")
            }
            Section {
                ScheduleActionRows(
                    session: session, scheduleId: scheduleId, summary: summary, stored: stored)
            } header: {
                Text("Actions")
            }
        }
    }

    private func titleString(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(
            separator: "\n", maxSplits: 1, omittingEmptySubsequences: true
        ).first
        return firstLine.map(String.init) ?? "Schedule"
    }
}
#endif
