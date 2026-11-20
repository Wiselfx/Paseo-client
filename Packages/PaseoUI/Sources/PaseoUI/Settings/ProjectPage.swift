#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One project's settings page, pushed under Projects. The page itself is `ProjectSettingsView`
/// (rename, icon, paseo.json and Remove project).
struct ProjectPage: View {
    let session: HostSession
    let projectID: String

    private var project: WorkspaceProjectDescriptor? {
        session.workspaceDirectory.project(id: projectID)
    }

    var body: some View {
        Group {
            if let project {
                ProjectSettingsView(session: session, project: project)
            } else {
                EmptyState(title: "Project not found")
                    .background(Palette.background)
            }
        }
    }
}
#endif
