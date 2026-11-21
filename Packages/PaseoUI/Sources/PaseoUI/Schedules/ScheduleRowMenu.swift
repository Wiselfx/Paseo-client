#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The verbs in a list row's context menu: pause or resume, run now (new-agent targets only),
/// edit, and Delete.
struct ScheduleRowMenu: View {
    let summary: ScheduleSummary
    let onSetPaused: (Bool) -> Void
    let onRunNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let isPaused = summary.status == .paused
        Button {
            Haptics.selection()
            onSetPaused(!isPaused)
        } label: {
            Label(isPaused ? "Resume schedule" : "Pause schedule", systemImage: isPaused ? "play" : "pause")
        }
        if summary.target.newAgentConfig != nil {
            Button {
                Haptics.light()
                onRunNow()
            } label: {
                Label("Run now", systemImage: "play.fill")
            }
        }
        Button(action: onEdit) {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete schedule", systemImage: "trash")
        }
    }
}
#endif
