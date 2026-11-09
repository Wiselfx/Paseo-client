#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension PaseoSidebar {
/// A quiet row under the last project; opens the Add-project sheet.
    var addProjectRow: some View {
        Button {
            Haptics.selection()
            sheet = .addProject
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(ClaudePalette.chip, in: .circle)
                Text("Add project")
                    .font(typography.sans(15))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add project")
    }

    func projectRow(_ group: WorkspaceGroup) -> some View {
        let collapsed = isCollapsed(group.id)
        let title = projectTitle(group.project)
        return HStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    toggleCollapsed(group.id)
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeChevron(expanded: !collapsed)
                    Text(title)
                        .font(typography.sans(15))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            Button {
                newAgent(in: group)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New agent in \(title)")
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .contextMenu {
            Button("New agent", systemImage: "plus") { newAgent(in: group) }
            Button("Rename…", systemImage: "pencil") {
                renameText = group.project.projectCustomName ?? ""
                renamingProject = group.project
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = group.project.projectRootPath
                showToast("Path copied")
            }
            if session.workspaceDirectory.supportsProjectRemove {
                Button("Remove project", systemImage: "trash", role: .destructive) {
                    projectPendingRemoval = group.project
                }
            }
        }
    }

    func projectTitle(_ project: WorkspaceProjectDescriptor) -> String {
        project.projectCustomName ?? project.projectDisplayName
    }

    /// The group's workspaces are already ordered by activity, so the head is the most recent one.
    func newAgent(in group: WorkspaceGroup) {
        guard let workspace = group.workspaces.first else {
            showToast("No workspace in this project yet — create one first.")
            return
        }
        Haptics.selection()
        onNewAgent(workspace)
    }

    // MARK: Collapse state

    var collapsedProjectsSet: Set<String> {
        Set(collapsedProjects.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    func isCollapsed(_ projectId: String) -> Bool {
        collapsedProjectsSet.contains(projectId)
    }

    func toggleCollapsed(_ projectId: String) {
        var collapsed = collapsedProjectsSet
        if collapsed.contains(projectId) {
            collapsed.remove(projectId)
        } else {
            collapsed.insert(projectId)
        }
        collapsedProjects = collapsed.sorted().joined(separator: ",")
    }
}
#endif
