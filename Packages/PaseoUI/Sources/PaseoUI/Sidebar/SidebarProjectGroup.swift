#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension PaseoSidebar {
    func projectRow(_ group: WorkspaceGroup) -> some View {
        SidebarProjectHeader(
            title: projectTitle(group.project),
            collapsed: isCollapsed(group.id),
            supportsRemove: session.workspaceDirectory.supportsProjectRemove
        ) { action in
            handleProjectAction(action, group: group)
        }
    }

    func handleProjectAction(_ action: SidebarProjectHeaderAction, group: WorkspaceGroup) {
        switch action {
        case .toggleCollapsed:
            toggleCollapsed(group.id)
        case .newSession:
            newSession(in: group)
        case .rename:
            renameText = group.project.projectCustomName ?? ""
            renamingProject = group.project
        case .openSettings:
            sheet = .project(group.project)
        case .copyPath:
            Clipboard.copy(group.project.projectRootPath)
            showToast("Path copied")
        case .remove:
            projectPendingRemoval = group.project
        }
    }

    func projectTitle(_ project: WorkspaceProjectDescriptor) -> String {
        project.projectCustomName ?? project.projectDisplayName
    }

    /// The group's workspaces are already ordered by activity, so the head is the most recent one.
    func newSession(in group: WorkspaceGroup) {
        guard let workspace = group.workspaces.first else {
            showToast("No workspaces in this project yet. Create one first.")
            return
        }
        // The shell settles the drawer and plays the one haptic (PLAN §RH).
        onNewSession(workspace.id)
    }

    // MARK: Collapse state

    func isCollapsed(_ projectId: String) -> Bool {
        preferences.isCollapsed(projectId: projectId)
    }

    func toggleCollapsed(_ projectId: String) {
        preferences.toggleCollapsed(projectId: projectId)
    }
}
#endif
