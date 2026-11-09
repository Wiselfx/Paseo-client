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
        let pinned = pinnedWorkspaces()
        switch sidebarGrouping {
        case .project:
            groupedDirectory(
                groups: sortedGroups(session.workspaceDirectory.groups), pinned: pinned)
        case .date:
            dateDirectory(buckets: dateBuckets(), pinned: pinned)
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
            pinnedSection(pinned)
            ForEach(groups) { group in
                projectRow(group)
                    .task(id: group.project.projectRootPath) {
                        await session.projectSetupProbe.check(repoRoot: group.project.projectRootPath)
                    }
                SidebarRoll(expanded: !isCollapsed(group.id)) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.workspaces) { workspace in
                            workspaceRow(workspace)
                        }
                        worktreeSetupCallout(group)
                    }
                    // Animated reorder (active-first); None under Reduce Motion.
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.3),
                        value: group.workspaces.map(\.id))
                }
            }
            trailingRows
        }
    }

    @ViewBuilder func dateDirectory(
        buckets: [SidebarDateBucket], pinned: [WorkspaceDescriptor]
    ) -> some View {
        let visible = buckets.filter { !$0.workspaces.isEmpty }
        let isEmpty = visible.isEmpty && pinned.isEmpty && hiddenWorkspacesSet.isEmpty
        if isEmpty {
            emptyDirectoryState
        } else {
            pinnedSection(pinned)
            ForEach(visible) { bucket in
                dateGroupHeader(bucket)
                SidebarRoll(expanded: !isDateGroupCollapsed(bucket.id)) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(bucket.workspaces) { workspace in
                            workspaceRow(workspace)
                        }
                    }
                    // Animated reorder (active-first); None under Reduce Motion.
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.3),
                        value: bucket.workspaces.map(\.id))
                }
            }
            trailingRows
        }
    }

    /// The date-group header, collapsible like a project row (persisted by bucket id).
    func dateGroupHeader(_ bucket: SidebarDateBucket) -> some View {
        let collapsed = isDateGroupCollapsed(bucket.id)
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                toggleDateGroupCollapsed(bucket.id)
            }
        } label: {
            HStack(spacing: 6) {
                ClaudeChevron(expanded: !collapsed)
                Text(bucket.title)
                    .font(typography.sans(15))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bucket.title)
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    /// The Pinned section, shared by both groupings.
    @ViewBuilder func pinnedSection(_ pinned: [WorkspaceDescriptor]) -> some View {
        if !pinned.isEmpty {
            sectionHeader("Pinned")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pinned) { workspace in
                    workspaceRow(workspace)
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.3),
                value: pinned.map(\.id))
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
        let filtered = labelFilterName != nil
        return Text(
            session.workspaceDirectory.isLoading
                ? "Loading workspaces…"
                : (filtered
                    ? "No workspaces with this label."
                    : (error ?? "No workspaces on this host yet."))
        )
        .font(typography.sans(14))
        .foregroundStyle(
            error == nil || filtered ? ClaudePalette.secondaryInk : ClaudePalette.failureInk
        )
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
            session.workspaceDirectory.workspaces.filter {
                $0.isPinned && isVisible($0) && matchesLabelFilter($0)
            })
    }

    /// A workspace counts as running when the daemon's own bucket says so, or any agent in it
    /// is running — the same signal the row's dot uses.
    func isRunningWorkspace(_ workspace: WorkspaceDescriptor) -> Bool {
        if workspace.status == .running { return true }
        return agents(in: workspace).contains { $0.status == .running }
    }

    func sortedWorkspaces(_ workspaces: [WorkspaceDescriptor]) -> [WorkspaceDescriptor] {
        let sorted: [WorkspaceDescriptor]
        switch sidebarSort {
        case .activity:
            sorted = workspaces.sorted {
                (activityDate(for: $0) ?? .distantPast) > (activityDate(for: $1) ?? .distantPast)
            }
        case .created:
            sorted = workspaces.sorted {
                let l = createdDate($0) ?? .distantPast
                let r = createdDate($1) ?? .distantPast
                if l == r { return $0.id > $1.id }
                return l > r
            }
        case .name:
            sorted = workspaces.sorted {
                workspaceTitle($0).localizedCaseInsensitiveCompare(workspaceTitle($1))
                    == .orderedAscending
            }
        }
        // Active first: running workspaces float to the head, stable otherwise.
        guard activeFirst else { return sorted }
        return sorted.filter(isRunningWorkspace) + sorted.filter { !isRunningWorkspace($0) }
    }

    func createdDate(_ workspace: WorkspaceDescriptor) -> Date? {
        workspace.createdAt.flatMap(PaseoDate.parse)
    }

    /// Date buckets per DSH `date-groups`: today, yesterday, weekday names for the last six
    /// days, then one `earlier` bucket for anything a week or more old. Same visible/label-
    /// filtered set as the project grouping; each bucket is sorted and floated (active-first).
    func dateBuckets() -> [SidebarDateBucket] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var byBucket: [String: [WorkspaceDescriptor]] = ["today": [], "yesterday": [], "earlier": []]
        for offset in 2...6 { byBucket["day-\(offset)"] = [] }
        let visible = session.workspaceDirectory.workspaces.filter {
            !$0.isPinned && isVisible($0) && matchesLabelFilter($0)
        }
        for workspace in visible {
            let date = activityDate(for: workspace)
            let start = date.map { calendar.startOfDay(for: $0) }
            let offset = start.map {
                calendar.dateComponents([.day], from: $0, to: startOfToday).day ?? 999
            }
            let key: String
            switch offset {
            case .some(let days) where days <= 0: key = "today"
            case .some(1): key = "yesterday"
            case .some(let days) where (2...6).contains(days): key = "day-\(days)"
            default: key = "earlier"
            }
            byBucket[key, default: []].append(workspace)
        }
        var buckets: [SidebarDateBucket] = [
            SidebarDateBucket(
                id: "today", title: "Today", workspaces: sortedWorkspaces(byBucket["today"] ?? [])),
            SidebarDateBucket(
                id: "yesterday", title: "Yesterday",
                workspaces: sortedWorkspaces(byBucket["yesterday"] ?? [])),
        ]
        let symbols = calendar.weekdaySymbols
        for offset in 2...6 {
            let start = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let weekdayIndex = calendar.component(.weekday, from: start) - 1
            let title = symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "Earlier"
            buckets.append(
                SidebarDateBucket(
                    id: "day-\(offset)", title: title,
                    workspaces: sortedWorkspaces(byBucket["day-\(offset)"] ?? [])))
        }
        buckets.append(
            SidebarDateBucket(
                id: "earlier", title: "Earlier",
                workspaces: sortedWorkspaces(byBucket["earlier"] ?? [])))
        return buckets
    }

    // MARK: Date-group collapse (persisted, like projects)

    var collapsedDateGroupsSet: Set<String> {
        Set(collapsedDateGroups.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    func isDateGroupCollapsed(_ id: String) -> Bool {
        collapsedDateGroupsSet.contains(id)
    }

    func toggleDateGroupCollapsed(_ id: String) {
        var collapsed = collapsedDateGroupsSet
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        collapsedDateGroups = collapsed.sorted().joined(separator: ",")
    }

    // MARK: Manual unread marks (persisted locally, DSH `manual-unread`)

    var manualUnreadSet: Set<String> {
        Set(manualUnread.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    func isManuallyUnread(_ workspace: WorkspaceDescriptor) -> Bool {
        manualUnreadSet.contains(workspace.id)
    }

    func toggleManualUnread(_ workspace: WorkspaceDescriptor) {
        var set = manualUnreadSet
        if set.contains(workspace.id) {
            set.remove(workspace.id)
        } else {
            set.insert(workspace.id)
        }
        manualUnread = set.sorted().joined(separator: ",")
    }

    /// Cleared when the workspace is opened.
    func clearManualUnread(_ workspace: WorkspaceDescriptor) {
        var set = manualUnreadSet
        guard set.remove(workspace.id) != nil else { return }
        manualUnread = set.sorted().joined(separator: ",")
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
                        group.workspaces.filter {
                            !$0.isPinned && isVisible($0) && matchesLabelFilter($0)
                        }))
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

/// One date bucket in the "Date" sidebar grouping: today / yesterday / earlier by last activity.
struct SidebarDateBucket: Identifiable {
    let id: String
    let title: String
    let workspaces: [WorkspaceDescriptor]
}
#endif
