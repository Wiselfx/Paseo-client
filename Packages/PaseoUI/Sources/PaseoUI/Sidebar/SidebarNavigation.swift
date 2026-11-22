#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The rows above the directory: Search, History, Schedules, Import session, Add project and New
/// workspace, each shown when enabled and supported.
struct SidebarNavigation: View {
    let session: HostSession
    let showHistory: Bool
    let showSchedules: Bool
    let onOpen: (PaseoSidebarSheet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ListRow(title: "Search", systemImage: "magnifyingglass") { onOpen(.search) }
            if showHistory {
                ListRow(title: "History", systemImage: "clock.arrow.2.circlepath") { onOpen(.history) }
            }
            if showSchedules {
                ListRow(title: "Schedules", systemImage: "clock") { onOpen(.schedules) }
            }
            if session.agentControl.isSupported {
                ListRow(title: "Import session", systemImage: "square.and.arrow.down") {
                    onOpen(.importSession)
                }
            }
            if session.workspaceDirectory.supportsProjectAdd {
                ListRow(title: "Add project", systemImage: "folder.badge.plus") { onOpen(.addProject) }
            }
            if session.workspaceDirectory.supportsWorkspaceCreate {
                ListRow(title: "New workspace", systemImage: "plus") { onOpen(.newWorkspace) }
            }
        }
        .padding(.top, 4)
    }
}
#endif
