#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The Remove project confirmation.
struct SidebarProjectRemovalDialog: ViewModifier {
    @Bindable var state: SidebarState
    let session: HostSession

    @Environment(\.toast) private var toast

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                ProjectActions.removeTitle,
                item: $state.projectPendingRemoval,
                titleVisibility: .visible
            ) { project in
                Button("Remove", role: .destructive) {
                    ProjectActions.remove(project, session: session, toast: toast)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(ProjectActions.removeMessage)
            }
    }
}
#endif
