#if canImport(UIKit)
import PaseoStore

/// Removing a project is one flow with one wording, wherever it is offered (audit C #18, PLAN
/// §RI 18): the sidebar's project menu and the project page present this confirmation and call
/// this action.
enum ProjectActions {
    static let removeTitle = "Remove project?"
    /// The sidebar's wording, unchanged.
    static let removeMessage =
        "The project and its workspaces will be unregistered on this host. Files on disk will not be changed."
    static let removedToast = "Project removed"
    static let removeFailure = "Couldn't remove the project."

    /// Unregisters the project and toasts the outcome. The caller has already asked.
    @MainActor static func remove(
        _ project: WorkspaceProjectDescriptor, session: HostSession, toast: ToastCenter?
    ) {
        let directory = session.workspaceDirectory
        let projectId = project.projectId
        Task {
            let removed = await directory.removeProject(projectId)
            toast?.show(removed ? removedToast : (directory.actionError ?? removeFailure))
        }
    }
}
#endif
