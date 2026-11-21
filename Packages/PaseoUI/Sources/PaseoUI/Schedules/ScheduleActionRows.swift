#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The detail page's Actions rows: pause or resume, run now, edit, and Delete. Delete asks first,
/// with the dialog attached to its own button, and pops back to the list when it succeeds.
struct ScheduleActionRows: View {
    let session: HostSession
    let scheduleId: String
    let summary: ScheduleSummary
    let stored: StoredSchedule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toast) private var toast

    @State private var confirmDelete = false

    private var schedules: SchedulesStore { session.schedules }

    var body: some View {
        let isPaused = summary.status == .paused
        ListRow(title: isPaused ? "Resume schedule" : "Pause schedule") {
            Haptics.selection()
            Task { await setPaused(paused: !isPaused) }
        }
        .panelRow()
        if summary.target.newAgentConfig != nil {
            ListRow(title: "Run now") {
                Haptics.light()
                Task { await runNow() }
            }
            .panelRow()
        }
        if let stored {
            PageLink(
                ClaudeSchedulesView.Route.editor(
                    ClaudeSchedulesView.EditorSeed(
                        stored: stored, isHeartbeat: stored.summary.target.agentId != nil)),
                title: "Edit schedule"
            )
            .accessibilityLabel("Edit schedule")
        }
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Text("Delete schedule")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .confirmationDialog(
            "Delete schedule?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs that already started finish, but no new runs will be created.")
        }
        .panelRow()
    }

    private func setPaused(paused: Bool) async {
        let ok = paused
            ? await schedules.pause(summary.id)
            : await schedules.resume(summary.id)
        if ok {
            toast?.show(paused ? "Paused" : "Resumed")
            _ = await schedules.inspect(scheduleId)
        } else {
            toast?.show(schedules.actionError ?? "Couldn't update the schedule.")
        }
    }

    private func runNow() async {
        if await schedules.runOnce(summary.id) {
            toast?.show("Run started")
            _ = await schedules.inspect(scheduleId)
        } else {
            toast?.show(schedules.actionError ?? "Couldn't start a run.")
        }
    }

    private func delete() async {
        if await schedules.delete(scheduleId) {
            toast?.show("Schedule deleted")
            dismiss()
        } else {
            toast?.show(schedules.actionError ?? "Couldn't delete the schedule.")
        }
    }
}
#endif
