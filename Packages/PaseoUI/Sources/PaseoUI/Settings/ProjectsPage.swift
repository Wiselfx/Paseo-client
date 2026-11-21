#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Settings → Host → Projects: every project this host reports, newest activity first. Each row
/// pushes that project's settings page, where Remove project lives (PLAN §RI 18).
struct ProjectsPage: View {
    let session: HostSession

    private var directory: WorkspaceDirectory { session.workspaceDirectory }

    private var projects: [WorkspaceProjectDescriptor] {
        directory.projects
            .sorted {
                ($0.projectCustomName ?? $0.projectDisplayName)
                    .localizedCaseInsensitiveCompare(
                        $1.projectCustomName ?? $1.projectDisplayName) == .orderedAscending
            }
    }

    private var counts: [String: Int] {
        var result: [String: Int] = [:]
        for workspace in directory.workspaces {
            result[workspace.projectId, default: 0] += 1
        }
        return result
    }

    var body: some View {
        PageList {
            Section {
                let projects = self.projects
                let counts = self.counts
                if projects.isEmpty {
                    EmptyState(
                        title: "No projects on this host yet",
                        message: "Add project from the sidebar."
                    )
                    .frame(minHeight: 180)
                    .panelRow(Palette.background)
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
                    InlineBanner(
                        .failure, title: error,
                        action: ("Try again", { Task { await session.workspaceDirectory.refresh() } }))
                        .panelRow(Palette.background)
                }
            }
        }
        .inlinePageTitle("Projects")
        .refreshable { await session.workspaceDirectory.refresh() }
    }

    private func projectRow(_ project: WorkspaceProjectDescriptor, count: Int) -> some View {
        PageLink(
            SettingsRoute.project(project.projectId),
            title: project.projectCustomName ?? project.projectDisplayName,
            subtitle: project.projectRootPath,
            detail: String(
                AttributedString(localized: "^[\(count) workspace](inflect: true)", bundle: #bundle).characters)
        )
        .accessibilityIdentifier("settings.projects.open.\(project.projectId)")
    }
}
#endif
