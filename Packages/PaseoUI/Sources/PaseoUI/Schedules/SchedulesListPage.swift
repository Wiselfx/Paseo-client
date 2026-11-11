#if canImport(UIKit)
import PaseoStore
import SwiftUI

// MARK: - List page

/// The Schedules list: one row per schedule, with the state pill and the next run. A row pushes
/// the detail page; the same verbs live in its context menu (PLAN §RH) and Delete also swipes.
/// No timer: `.task` polls while the list is on screen, and only while the app is active.
struct SchedulesListPage: View {
    let session: HostSession
    let onNew: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toast) private var toast

    @State private var now = Date()
    @State private var editorRequest: ClaudeSchedulesView.EditorSeed?
    @State private var deleteRequest: ScheduleSummary?

    private var schedules: SchedulesStore { session.schedules }
    private var knownAgentIds: Set<String> { Set(session.agents.map(\.id)) }

    var body: some View {
        Group {
            if !schedules.isSupported {
                unsupportedState
            } else if case .failed(let message) = schedules.phase, schedules.schedules.isEmpty {
                failedState(message)
            } else if (schedules.phase == .idle || schedules.phase == .loading),
                schedules.schedules.isEmpty
            {
                LoadingState()
            } else if schedules.schedules.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editorRequest) { seed in
            ScheduleEditorPage(session: session, seed: seed)
        }
        .task {
            // No push events for schedules: the captions tick every 5 s from the local
            // `now`, and the list itself reloads every 30 s (minute-granularity data) plus on
            // appear, pull-to-refresh and every mutation. The store publishes only on real
            // change, so a quiet poll never re-evaluates the rows.
            var tick = 0
            while !Task.isCancelled {
                if scenePhase == .active {
                    now = Date()
                    if tick % 6 == 0 { await schedules.load() }
                    tick += 1
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog(
            "Delete schedule?",
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let summary = deleteRequest else { return }
                deleteRequest = nil
                Task { await delete(summary) }
            }
            Button("Cancel", role: .cancel) { deleteRequest = nil }
        } message: {
            Text("Runs that already started finish, but no new runs will be created.")
        }
    }

    private var list: some View {
        List {
            if let actionError = schedules.actionError {
                Section {
                    InlineBanner(.failure, title: actionError)
                        .panelRow(Palette.background)
                }
            }
            Section {
                ForEach(schedules.schedules) { summary in
                    row(summary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .refreshable { await schedules.load() }
    }

    private func row(_ summary: ScheduleSummary) -> some View {
        let state = summary.state(now: now, knownAgentIds: knownAgentIds)
        return NavigationLink(value: ClaudeSchedulesView.Route.detail(summary.id)) {
            HStack(spacing: 0) {
                ListRow(title: title(summary), subtitle: summary.cadence.words)
                VStack(alignment: .trailing, spacing: Space.xs) {
                    ScheduleStatePill(state: state)
                    Text(nextCaption(summary, state: state))
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.captionInk)
                }
                .padding(.trailing, Space.lg)
            }
        }
        .panelRow()
        .accessibilityLabel("Schedule \(title(summary))")
        .accessibilityValue("\(summary.cadence.words), \(nextCaption(summary, state: state))")
        .contextMenu {
            rowMenu(summary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteRequest = summary
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private func rowMenu(_ summary: ScheduleSummary) -> some View {
        let isPaused = summary.status == .paused
        Button {
            Haptics.selection()
            Task { await setPaused(summary, paused: !isPaused) }
        } label: {
            Label(isPaused ? "Resume schedule" : "Pause schedule", systemImage: isPaused ? "play" : "pause")
        }
        if summary.target.newAgentConfig != nil {
            Button {
                Haptics.light()
                Task { await runNow(summary) }
            } label: {
                Label("Run now", systemImage: "play.fill")
            }
        }
        Button {
            Task { await edit(summary) }
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            deleteRequest = summary
        } label: {
            Label("Delete schedule", systemImage: "trash")
        }
    }

    // MARK: Actions

    private func setPaused(_ summary: ScheduleSummary, paused: Bool) async {
        let ok = paused
            ? await schedules.pause(summary.id)
            : await schedules.resume(summary.id)
        if ok {
            toast?.show(paused ? "Paused" : "Resumed")
        } else {
            toast?.show(schedules.actionError ?? "Couldn't update the schedule.")
        }
    }

    /// The editor needs the full record, so inspect first when this row has not been opened.
    private func edit(_ summary: ScheduleSummary) async {
        let isHeartbeat = summary.target.agentId != nil
        if schedules.selected?.id != summary.id {
            _ = await schedules.inspect(summary.id)
        }
        guard let stored = schedules.selected, stored.id == summary.id else {
            toast?.show(schedules.actionError ?? "Still loading this schedule.")
            return
        }
        editorRequest = ClaudeSchedulesView.EditorSeed(stored: stored, isHeartbeat: isHeartbeat)
    }

    private func runNow(_ summary: ScheduleSummary) async {
        if await schedules.runOnce(summary.id) {
            toast?.show("Run started")
        } else {
            toast?.show(schedules.actionError ?? "Couldn't start a run.")
        }
        await schedules.load()
    }

    private func delete(_ summary: ScheduleSummary) async {
        if await schedules.delete(summary.id) {
            toast?.show("Schedule deleted")
        } else {
            toast?.show(schedules.actionError ?? "Couldn't delete the schedule.")
        }
    }

    // MARK: Text

    private func title(_ summary: ScheduleSummary) -> String {
        if let name = summary.name, !name.isEmpty { return name }
        let firstLine = summary.prompt.split(
            separator: "\n", maxSplits: 1, omittingEmptySubsequences: true
        ).first
        return firstLine.map(String.init) ?? "Untitled schedule"
    }

    private func nextCaption(_ summary: ScheduleSummary, state: ScheduleState) -> String {
        switch state {
        case .paused: return "Paused"
        case .expired, .finished: return "No upcoming run"
        default: return scheduleNextRun(summary.nextRunAt)
        }
    }

    // MARK: States

    private var emptyState: some View {
        EmptyState(
            systemImage: "clock",
            title: "No schedules yet",
            message: "Schedules run agents on a cadence.",
            action: (title: "New schedule", run: {
                onNew()
            })
        )
        .accessibilityIdentifier("schedules.empty")
    }

    private var unsupportedState: some View {
        EmptyState(
            systemImage: "clock",
            title: "Schedules aren't available on this host",
            message: "The host did not grant permission to manage schedules."
        )
    }

    private func failedState(_ message: String) -> some View {
        EmptyState(
            systemImage: "exclamationmark.triangle",
            title: message,
            message: nil,
            action: (title: "Try again", run: {
                Task { await schedules.load() }
            })
        )
    }
}
#endif
