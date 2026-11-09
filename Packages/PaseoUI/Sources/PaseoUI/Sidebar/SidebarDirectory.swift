#if canImport(UIKit)
import PaseoStore
import SwiftUI

extension PaseoSidebar {
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ClaudePalette.tertiaryInk)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    @ViewBuilder var directory: some View {
        let groups = sortedGroups(session.workspaceDirectory.groups)
        let pinned = pinnedWorkspaces()
        if groupByProject {
            groupedDirectory(groups: groups, pinned: pinned)
        } else {
            flatDirectory(flat: flatWorkspaces, pinned: pinned)
        }
    }

    @ViewBuilder func groupedDirectory(
        groups: [WorkspaceGroup], pinned: [WorkspaceDescriptor]
    ) -> some View {
        let isEmpty =
            groups.allSatisfy { $0.workspaces.isEmpty } && pinned.isEmpty
            && hiddenWorkspacesSet.isEmpty
        if isEmpty {
            emptyDirectoryState
        } else {
            if !pinned.isEmpty {
                sectionHeader("Pinned")
                ForEach(pinned) { workspace in
                    workspaceRow(workspace)
                }
            }
            ForEach(groups) { group in
                projectRow(group)
                SidebarRoll(expanded: !isCollapsed(group.id)) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.workspaces) { workspace in
                            workspaceRow(workspace)
                        }
                    }
                }
            }
            trailingRows
        }
    }

    @ViewBuilder func flatDirectory(
        flat: [WorkspaceDescriptor], pinned: [WorkspaceDescriptor]
    ) -> some View {
        if flat.isEmpty, pinned.isEmpty, hiddenWorkspacesSet.isEmpty {
            emptyDirectoryState
        } else {
            if !pinned.isEmpty {
                sectionHeader("Pinned")
                ForEach(pinned) { workspace in
                    workspaceRow(workspace)
                }
            }
            ForEach(flat) { workspace in
                workspaceRow(workspace)
            }
            trailingRows
        }
    }

    @ViewBuilder var trailingRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.workspaceDirectory.supportsProjectAdd {
                addProjectRow
            }
            if !hiddenWorkspacesSet.isEmpty {
                hiddenWorkspacesRow
            }
        }
    }

    var hiddenWorkspacesRow: some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showHidden.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(ClaudePalette.chip, in: .circle)
                Text("Hidden workspaces (\(hiddenWorkspacesSet.count))")
                    .font(typography.sans(15))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Spacer(minLength: 0)
                ClaudeChevron(expanded: showHidden)
            }
            .padding(.top, 12)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            showHidden
                ? "Hide hidden workspaces"
                : "Show hidden workspaces")
    }

    var emptyDirectoryState: some View {
        let error = session.workspaceDirectory.error
        return Text(
            session.workspaceDirectory.isLoading
                ? "Loading workspaces…"
                : (error ?? "No workspaces on this host yet.")
        )
        .font(typography.sans(14))
        .foregroundStyle(error == nil ? ClaudePalette.secondaryInk : ClaudePalette.failureInk)
        .padding(.vertical, 24)
    }

    

    // MARK: Visibility and ordering

    var sidebarSort: SidebarSort {
        SidebarSort(rawValue: sortRaw) ?? .activity
    }

    var hiddenWorkspacesSet: Set<String> {
        Set(hiddenWorkspaces.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    /// Hidden rows show up only while the "Hidden workspaces" row is expanded.
    func isVisible(_ workspace: WorkspaceDescriptor) -> Bool {
        showHidden || !hiddenWorkspacesSet.contains(workspace.id)
    }

    /// Persisted client-side set of hidden workspace ids (`paseo.sidebar.hiddenWorkspaces`).
    func isHiddenFromSidebar(_ workspace: WorkspaceDescriptor) -> Bool {
        hiddenWorkspacesSet.contains(workspace.id)
    }

    func toggleHiddenFromSidebar(_ workspace: WorkspaceDescriptor) {
        var set = hiddenWorkspacesSet
        if set.contains(workspace.id) { set.remove(workspace.id) } else { set.insert(workspace.id) }
        hiddenWorkspaces = set.sorted().joined(separator: ",")
    }

    /// Pinned workspaces, newest activity first.
    func pinnedWorkspaces() -> [WorkspaceDescriptor] {
        sortedWorkspaces(
            session.workspaceDirectory.workspaces.filter { $0.isPinned && isVisible($0) })
    }

    func sortedWorkspaces(_ workspaces: [WorkspaceDescriptor]) -> [WorkspaceDescriptor] {
        switch sidebarSort {
        case .activity:
            workspaces.sorted {
                (activityDate(for: $0) ?? .distantPast) > (activityDate(for: $1) ?? .distantPast)
            }
        case .created:
            workspaces.sorted {
                let l = createdDate($0) ?? .distantPast
                let r = createdDate($1) ?? .distantPast
                if l == r { return $0.id > $1.id }
                return l > r
            }
        case .name:
            workspaces.sorted {
                workspaceTitle($0).localizedCaseInsensitiveCompare(workspaceTitle($1))
                    == .orderedAscending
            }
        }
    }

    func createdDate(_ workspace: WorkspaceDescriptor) -> Date? {
        workspace.createdAt.flatMap(PaseoDate.parse)
    }

    var flatWorkspaces: [WorkspaceDescriptor] {
        sortedWorkspaces(
            session.workspaceDirectory.workspaces.filter { !$0.isPinned && isVisible($0) })
    }

    /// Workspaces within a project per the sidebar sort; projects ordered by their newest
    /// workspace (max of the sidebar sort key), name-sorted in "Name" mode. Pinned workspaces
    /// live in their own section and are excluded here, as are hidden rows.
    func sortedGroups(_ groups: [WorkspaceGroup]) -> [WorkspaceGroup] {
        groups
            .map { group in
                WorkspaceGroup(
                    project: group.project,
                    workspaces: sortedWorkspaces(
                        group.workspaces.filter { !$0.isPinned && isVisible($0) }))
            }
            .sorted { left, right in
                if sidebarSort == .name {
                    return left.project.projectDisplayName.localizedCaseInsensitiveCompare(
                        right.project.projectDisplayName) == .orderedAscending
                }
                let leftDate = left.workspaces.compactMap(groupSortDate).max() ?? .distantPast
                let rightDate = right.workspaces.compactMap(groupSortDate).max() ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.project.projectDisplayName.localizedCaseInsensitiveCompare(
                    right.project.projectDisplayName) == .orderedAscending
            }
    }

    func groupSortDate(_ workspace: WorkspaceDescriptor) -> Date? {
        sidebarSort == .created ? createdDate(workspace) : activityDate(for: workspace)
    }

    func activityDate(for workspace: WorkspaceDescriptor) -> Date? {
        var best: Date?
        for agent in session.agents where agent.workspaceId == workspace.id {
            for stamp in [agent.updatedAt, agent.lastUserMessageAt] {
                guard let stamp, let date = PaseoDate.parse(stamp) else { continue }
                best = max(best ?? date, date)
            }
        }
        if let best { return best }
        for stamp in [workspace.activityAt, workspace.lastUserMessageAt, workspace.createdAt] {
            if let stamp, let date = PaseoDate.parse(stamp) { return date }
        }
        return nil
    }
}
#endif
