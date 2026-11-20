#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// What a row can do. One object per directory pass, shared by every row; rows compare equal
/// without it (the closures it reaches are the sidebar's stable `@State` and the shell's actions).
@MainActor
final class SidebarRowActions {
    private let sidebar: PaseoSidebar

    init(sidebar: PaseoSidebar) {
        self.sidebar = sidebar
    }

    /// Tapping a workspace opens its most recently active agent; the other agents are the header's
    /// tab chips. Opening also clears a manual unread mark.
    func open(_ workspace: WorkspaceDescriptor, firstAgentId: String?) {
        // The tap moves the drawer, so the shell owns the haptic (PLAN §RH).
        sidebar.clearManualUnread(workspace)
        guard let firstAgentId else {
            // No agent yet: a draft in this workspace, like Search (audit C #6).
            sidebar.onNewSession(workspace.id)
            return
        }
        sidebar.onSelectAgent(firstAgentId)
    }

    func newSession(_ workspace: WorkspaceDescriptor) { sidebar.onNewSession(workspace.id) }

    func rename(_ workspace: WorkspaceDescriptor) {
        sidebar.renameText = workspace.title ?? workspace.name
        sidebar.renamingWorkspace = workspace
    }

    func togglePinned(_ workspace: WorkspaceDescriptor) {
        let session = sidebar.session
        Task {
            let ok = await session.workspaceDirectory.setPinned(workspace.id, !workspace.isPinned)
            if !ok {
                sidebar.showToast(session.workspaceDirectory.actionError ?? "Couldn't change the pin.")
            }
        }
    }

    func toggleUnread(_ workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleManualUnread(workspace)
    }

    func toggleLabel(_ label: WorkspaceLabelDefinition, on workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleLabel(label, on: workspace)
    }

    func newLabel(on workspace: WorkspaceDescriptor) { sidebar.sheet = .newLabel(workspace) }

    func copyPath(_ workspace: WorkspaceDescriptor) {
        Clipboard.copy(workspace.cwd)
        sidebar.showToast("Path copied")
    }

    func copyBranch(_ branch: String) {
        Clipboard.copy(branch)
        sidebar.showToast("Branch name copied")
    }

    func toggleHidden(_ workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleHiddenFromSidebar(workspace)
    }

    func archive(_ workspace: WorkspaceDescriptor) {
        sidebar.archive.request(workspace, session: sidebar.session, toast: sidebar.toast)
    }
}
#endif
