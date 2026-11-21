import PaseoStore
import SwiftUI

/// The archive flow's two destructive confirmations, attached by every surface that offers
/// "Archive workspace" (the sidebar row menu and the workspace panel's actions menu), so the
/// copy and the order can't drift.
struct WorkspaceArchiveDialogs: ViewModifier {
    let archive: WorkspaceArchiveActions
    let session: HostSession
    @Environment(\.toast) private var toast

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Archive worktree?",
                item: Bindable(archive).pendingWarning,
                titleVisibility: .visible
            ) { _ in
                Button("Archive", role: .destructive) {
                    archive.confirmWarning(session: session, toast: toast)
                }
                Button("Cancel", role: .cancel) {}
            } message: { warning in
                Text(warning.message)
            }
            .confirmationDialog(
                "Archive workspace?",
                item: Bindable(archive).pendingConfirmation,
                titleVisibility: .visible
            ) { _ in
                Button("Archive", role: .destructive) {
                    archive.confirmPending(session: session, toast: toast)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its agents and terminals stop. This host can't undo an archive.")
            }
    }
}

extension View {
    func workspaceArchiveDialogs(
        _ archive: WorkspaceArchiveActions, session: HostSession
    ) -> some View {
        modifier(WorkspaceArchiveDialogs(archive: archive, session: session))
    }
}
