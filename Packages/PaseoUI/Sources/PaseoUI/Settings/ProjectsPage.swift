#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Projects: every project this host reports, newest activity first. Each row
/// pushes that project's settings page, where Remove project lives (PLAN §RI 18).
struct ProjectsPage: View {
    let session: HostSession

    private var directory: WorkspaceDirectory { session.workspaceDirectory }

    private var projects: [WorkspaceProjectDescriptor] {
        directory.groups
            .map(\.project)
            .sorted {
                ($0.projectCustomName ?? $0.projectDisplayName)
                    .localizedCaseInsensitiveCompare(
                        $1.projectCustomName ?? $1.projectDisplayName) == .orderedAscending
            }
    }

    private var counts: [String: Int] {
        var result: [String: Int] = [:]
        for group in directory.groups {
            result[group.project.projectId, default: 0] += group.workspaces.count
        }
        return result
    }

    var body: some View {
        SettingsList {
            Section {
                if projects.isEmpty {
                    EmptyState(
                        title: "No projects on this host yet",
                        message: "Add a project from the sidebar."
                    )
                    .frame(minHeight: 180)
                    .settingsListRow(Palette.background)
                } else {
                    ForEach(projects) { project in
                        projectRow(project, count: counts[project.id] ?? 0)
                    }
                }
            } header: {
                Text("On this host")
            } footer: {
                Text("Removing a project unregisters it on this host. Files on disk are not changed.")
            }
            if let error = directory.actionError {
                Section {
                    InlineBanner(.failure, title: error)
                        .settingsListRow(Palette.background)
                }
            }
        }
        .settingsPage("Projects")
        .refreshable { await session.hostSettings.load() }
    }

    private func projectRow(_ project: WorkspaceProjectDescriptor, count: Int) -> some View {
        NavigationLink(value: SettingsRoute.project(project.projectId)) {
            ListRow(
                title: project.projectCustomName ?? project.projectDisplayName,
                subtitle: project.projectRootPath,
                accessory: ListRow.Accessory.value(
                    count == 1 ? "1 workspace" : "\(count) workspaces")
            )
        }
        .settingsListRow()
        .accessibilityIdentifier("settings.projects.open.\(project.projectId)")
    }
}

/// One project's settings page, pushed under Projects. The page itself is `ProjectSettingsView`
/// (rename, icon, paseo.json and Remove project).
struct ProjectPage: View {
    let session: HostSession
    let projectID: String

    private var project: WorkspaceProjectDescriptor? {
        session.workspaceDirectory.groups.map(\.project).first { $0.projectId == projectID }
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
