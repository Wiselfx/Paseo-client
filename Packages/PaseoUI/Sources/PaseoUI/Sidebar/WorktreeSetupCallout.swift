#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The quiet "Set up worktree scripts" callout shown under a project that has worktree
/// workspaces but no `worktree.setup` in its `paseo.json` (M2.11's `ProjectConfigStore`, read
/// through a throwaway probe — see `ProjectSetupProbe`).
///
/// Hidden until the probe answers; a failed read stays quiet (the probe caches `failed`).
/// Tapping the body opens the M2.11 Project page; the xmark dismisses it, persisted per
/// project in `SidebarPreferences.setupCalloutDismissed`.
///
/// Mirrors upstream's `worktree-setup-callout-source` policy: git project, no setup commands,
/// dismissal key per project. Shown in the project (grouped) sidebar only — the date grouping
/// has no project headers to sit under.
extension PaseoSidebar {
    @ViewBuilder func worktreeSetupCallout(_ group: WorkspaceGroup) -> some View {
        if shouldShowWorktreeSetupCallout(group) {
            SidebarWorktreeSetupCallout {
                sheet = .project(group.project)
            } onDismiss: {
                dismissWorktreeSetupCallout(group.project.projectId)
            }
        }
    }

    func shouldShowWorktreeSetupCallout(_ group: WorkspaceGroup) -> Bool {
        guard group.project.projectKind == .git else { return false }
        let hasWorktree = session.workspaceDirectory.workspaces.contains {
            $0.projectId == group.project.projectId && $0.workspaceKind == .worktree
        }
        guard hasWorktree else { return false }
        guard !preferences.isSetupCalloutDismissed(projectId: group.project.projectId) else {
            return false
        }
        return session.projectSetupProbe.hasSetupCommands[group.project.projectRootPath] == false
    }

    func dismissWorktreeSetupCallout(_ projectId: String) {
        preferences.dismissSetupCallout(projectId: projectId)
    }
}
#endif
