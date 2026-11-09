#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension PaseoSidebar {
    /// Archives a workspace (confirmed first when the host can't undo; else the undo toast is the
    /// safety net) and surfaces the outcome as a bottom toast with an Undo for ~5 s.
    func archiveWorkspace(_ workspace: WorkspaceDescriptor) {
        let supportsUndo = session.workspaceDirectory.supportsWorkspaceArchiveUndo
        Task {
            let archived = await session.workspaceDirectory.archiveWorkspaceWithUndo(workspace.id)
            guard archived else {
                showToast(
                    session.workspaceDirectory.actionError ?? "Couldn't archive the workspace.")
                return
            }
            if supportsUndo {
                showArchiveToast(for: workspace)
            } else {
                showToast("Archived \(workspaceTitle(workspace))")
            }
        }
    }

    func showArchiveToast(for workspace: WorkspaceDescriptor) {
        let name = workspaceTitle(workspace)
        let token = UUID()
        undoToastToken = token
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            undoToast = (workspace.id, name)
        }
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: "Workspace archived: \(name). Undo is available.")
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard undoToastToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                undoToast = nil
            }
        }
    }

    func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}
#endif
