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
    /// Opens the editor for a stored schedule; the parent owns the single editor destination.
    let onEdit: (ClaudeSchedulesView.EditorSeed) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.toast) private var toast

    @State private var now = Date.now
    @State private var deleteRequest: ScheduleSummary?

    private var schedules: SchedulesStore { session.schedules }
    /// Built once per pass, and only when a schedule targets an agent: `state` consults it for those
    /// alone. It used to be rebuilt from every agent for every row.
    private func knownAgentIds() -> Set<String>? {
        guard schedules.schedules.contains(where: {
            if case .agent = $0.target { return true }
            return false
        }) else { return nil }
        return Set(session.agents.map(\.id))
    }

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
        .task(id: scenePhase) {
            // Restarted on every scene phase change, so the loop never polls while the app is
            // inactive or in the background, and reloads at once when it becomes active again.
            guard scenePhase == .active else { return }
            await poll()
        }
        .confirmationDialog(
            "Delete schedule?",
            item: $deleteRequest,
            titleVisibility: .visible
        ) { summary in
            Button("Delete", role: .destructive) {
                Task { await delete(summary) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
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
                let known = knownAgentIds()
                ForEach(schedules.schedules) { summary in
                    ScheduleListRow(
                        summary: summary,
                        knownAgentIds: known,
                        now: now,
                        onSetPaused: { paused in Task { await setPaused(summary, paused: paused) } },
                        onRunNow: { Task { await runNow(summary) } },
                        onEdit: { Task { await edit(summary) } },
                        onDelete: { deleteRequest = summary })
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .refreshable { await schedules.load() }
    }

    // MARK: Actions

    /// No push events for schedules: the captions tick every 5 s from the local `now`, and the
    /// list itself reloads every 30 s (minute-granularity data) plus on appear, pull-to-refresh
    /// and every mutation. The store publishes only on real change, so a quiet poll never
    /// re-evaluates the rows.
    private func poll() async {
        var tick = 0
        while !Task.isCancelled {
            now = .now
            if tick % 6 == 0 { await schedules.load() }
            tick += 1
            try? await Task.sleep(for: .seconds(5))
        }
    }

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
        onEdit(ClaudeSchedulesView.EditorSeed(stored: stored, isHeartbeat: isHeartbeat))
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
