#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The Rename workspace and Rename project alerts, and the renames they send.
struct SidebarRenameAlerts: ViewModifier {
    @Bindable var state: SidebarState
    let session: HostSession

    @Environment(\.toast) private var toast

    func body(content: Content) -> some View {
        content
            .alert("Rename workspace", item: $state.renamingWorkspace) { workspace in
                TextField("Name", text: $state.renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { renameWorkspace(workspace, to: state.renameText) }
            } message: { _ in
                Text("Choose a short name for this workspace.")
            }
            .alert("Rename project", item: $state.renamingProject) { project in
                TextField("Folder name", text: $state.renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { renameProject(project, to: state.renameText) }
            } message: { _ in
                Text("Empty restores the folder name.")
            }
    }

    /// An empty name keeps the workspace as it was.
    private func renameWorkspace(_ target: WorkspaceDescriptor, to text: String) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            let renamed = await session.workspaceDirectory.renameWorkspace(target.id, title: title)
            if !renamed {
                toast?.show(session.workspaceDirectory.actionError ?? "Couldn't rename the workspace.")
            }
        }
    }

    /// An empty name restores the folder name.
    private func renameProject(_ target: WorkspaceProjectDescriptor, to text: String) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let renamed = await session.workspaceDirectory.renameProject(target.projectId, to: title)
            if !renamed {
                toast?.show(session.workspaceDirectory.actionError ?? "Couldn't rename the project.")
            }
        }
    }
}
#endif
