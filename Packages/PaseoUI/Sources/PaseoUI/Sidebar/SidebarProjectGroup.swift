#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension PaseoSidebar {
    func projectRow(_ group: WorkspaceGroup) -> some View {
        let collapsed = isCollapsed(group.id)
        let title = projectTitle(group.project)
        return HStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                    toggleCollapsed(group.id)
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeChevron(expanded: !collapsed)
                    Text(title)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            Button {
                newSession(in: group)
            } label: {
                Image(systemName: "plus")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 30, height: 30)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New session in \(title)")
        }
        // A collapsed group is a 44 pt hit row at the sidebar's action-row pitch: 8 pt above,
        // nothing below (E2b §11). The workspace rows carry their own vertical padding, so the
        // first one does not crowd the header when the group expands.
        .padding(.top, Space.sm)
        .contextMenu {
            // PLAN §RH order: open-variants, edit verbs, copy, then the destructive verb.
            Button("New session", systemImage: "plus") { newSession(in: group) }
            Button("Rename…", systemImage: "pencil") {
                renameText = group.project.projectCustomName ?? ""
                renamingProject = group.project
            }
            Button("Project settings…", systemImage: "gearshape") {
                sheet = .project(group.project)
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                Clipboard.copy(group.project.projectRootPath)
                showToast("Path copied")
            }
            if session.workspaceDirectory.supportsProjectRemove {
                Divider()
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
    func newSession(in group: WorkspaceGroup) {
        guard let workspace = group.workspaces.first else {
            showToast("No workspaces in this project yet. Create one first.")
            return
        }
        // The shell settles the drawer and plays the one haptic (PLAN §RH).
        onNewSession(workspace.id)
    }

    // MARK: Collapse state

    func isCollapsed(_ projectId: String) -> Bool {
        preferences.isCollapsed(projectId: projectId)
    }

    func toggleCollapsed(_ projectId: String) {
        preferences.toggleCollapsed(projectId: projectId)
    }
}
#endif
