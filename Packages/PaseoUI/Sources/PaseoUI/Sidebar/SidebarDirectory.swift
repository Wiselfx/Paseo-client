#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Derived once per sidebar body evaluation (P5 finding #3): the workspace→agents and
/// workspace→last-activity tables. The directory and every row share one pass over
/// `session.agents` and one date parse per workspace instead of one scan/parse per row.
struct SidebarDerivations {
    let agentsByWorkspace: [String: [AgentSnapshot]]
    let activityDates: [String: Date]
}

extension PaseoSidebar {
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.footnote, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    /// Builds the shared tables once per body evaluation. `activityDate` parses up to five
    /// ISO-8601 stamps per workspace; doing that per row (or per sort comparison) was the
    /// sidebar's hot path (P3/P5 finding #3).
    func sidebarDerivations() -> SidebarDerivations {
        var agentsByWorkspace: [String: [AgentSnapshot]] = [:]
        for agent in session.agents {
            guard let workspaceId = agent.workspaceId else { continue }
            agentsByWorkspace[workspaceId, default: []].append(agent)
        }
        var activityDates: [String: Date] = [:]
        for workspace in session.workspaceDirectory.workspaces {
            if let date = activityDate(for: workspace, agents: agentsByWorkspace[workspace.id] ?? []) {
                activityDates[workspace.id] = date
            }
        }
        return SidebarDerivations(
            agentsByWorkspace: agentsByWorkspace, activityDates: activityDates)
    }

    @ViewBuilder func directory(derivations: SidebarDerivations) -> some View {
        let pinned = pinnedWorkspaces(derivations: derivations)
        switch sidebarGrouping {
        case .project:
            groupedDirectory(
                groups: sortedGroups(session.workspaceDirectory.groups, derivations: derivations),
                pinned: pinned,
                derivations: derivations)
        case .date:
            dateDirectory(
                buckets: dateBuckets(derivations: derivations),
                pinned: pinned,
                derivations: derivations)
        }
    }

    @ViewBuilder func groupedDirectory(
        groups: [WorkspaceGroup], pinned: [WorkspaceDescriptor], derivations: SidebarDerivations
    ) -> some View {
        let isEmpty =
            groups.allSatisfy { $0.workspaces.isEmpty } && pinned.isEmpty
            && preferences.hiddenWorkspaces.isEmpty
        if isEmpty {
            emptyDirectoryState
        } else {
            // Lazy so a large project list mounts only the groups near the viewport; the
            // ForEach must be a direct child of the lazy stack to virtualize (P5 #3).
            LazyVStack(alignment: .leading, spacing: 0) {
                pinnedSection(pinned, derivations: derivations)
                ForEach(groups) { group in
                    projectRow(group)
                        .task(id: group.project.projectRootPath) {
                            await session.projectSetupProbe.check(repoRoot: group.project.projectRootPath)
                        }
                    SidebarRoll(expanded: !isCollapsed(group.id)) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(group.workspaces) { workspace in
                                workspaceRow(workspace, derivations: derivations)
                            }
                            worktreeSetupCallout(group)
                        }
                        // Animated reorder (active-first); None under Reduce Motion.
                        .animation(
                            Motion.settle.resolved(reduceMotion: reduceMotion),
                            value: group.workspaces.map(\.id))
                    }
                }
                trailingRows
            }
        }
    }

    @ViewBuilder func dateDirectory(
        buckets: [SidebarDateBucket], pinned: [WorkspaceDescriptor],
        derivations: SidebarDerivations
    ) -> some View {
        let visible = buckets.filter { !$0.workspaces.isEmpty }
        let isEmpty = visible.isEmpty && pinned.isEmpty && preferences.hiddenWorkspaces.isEmpty
        if isEmpty {
            emptyDirectoryState
        } else {
            // Lazy for the same reason as the project grouping (P5 #3).
            LazyVStack(alignment: .leading, spacing: 0) {
                pinnedSection(pinned, derivations: derivations)
                ForEach(visible) { bucket in
                    dateGroupHeader(bucket)
                    SidebarRoll(expanded: !isDateGroupCollapsed(bucket.id)) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(bucket.workspaces) { workspace in
                                workspaceRow(workspace, derivations: derivations)
                            }
                        }
                        // Animated reorder (active-first); None under Reduce Motion.
                        .animation(
                            Motion.settle.resolved(reduceMotion: reduceMotion),
                            value: bucket.workspaces.map(\.id))
                    }
                }
                trailingRows
            }
        }
    }

    /// The date-group header, collapsible like a project row (persisted by bucket id).
    func dateGroupHeader(_ bucket: SidebarDateBucket) -> some View {
        let collapsed = isDateGroupCollapsed(bucket.id)
        return Button {
            Haptics.selection()
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                toggleDateGroupCollapsed(bucket.id)
            }
        } label: {
            HStack(spacing: 6) {
                ClaudeChevron(expanded: !collapsed)
                Text(bucket.title)
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
    @ViewBuilder func pinnedSection(
        _ pinned: [WorkspaceDescriptor], derivations: SidebarDerivations
    ) -> some View {
        if !pinned.isEmpty {
            sectionHeader("Pinned")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pinned) { workspace in
                    workspaceRow(workspace, derivations: derivations)
                }
            }
            .animation(
                Motion.settle.resolved(reduceMotion: reduceMotion),
                value: pinned.map(\.id))
        }
    }

    /// Add project moved into the navigation rows above the directory (§2.3); the directory
    /// keeps only the hidden-workspaces disclosure.
    @ViewBuilder var trailingRows: some View {
        if !preferences.hiddenWorkspaces.isEmpty {
            hiddenWorkspacesRow
        }
    }

    var hiddenWorkspacesRow: some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) { showHidden.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: 24, height: 24)
                    .background(Palette.chip, in: .circle)
                Text("Hidden workspaces (\(PaseoFormat.integer(preferences.hiddenWorkspaces.count)))")
                    .font(.paseo(.callout))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
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

    /// An error is a banner with a retry (PLAN §RI 22); everything else is the quiet line.
    @ViewBuilder var emptyDirectoryState: some View {
        if let error = session.workspaceDirectory.error, labelFilterName == nil {
            InlineBanner(.failure, title: error, action: ("Try again", retryDirectory))
                .padding(.vertical, 24)
        } else {
            if session.workspaceDirectory.isLoading {
                LoadingState("Loading workspaces…")
                    .padding(.vertical, 24)
            } else {
                Text(
                    labelFilterName == nil
                        ? "No workspaces on this host yet."
                        : "No workspaces with this label."
                )
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.vertical, 24)
            }
        }
    }

    

    // MARK: Visibility and ordering

    var sidebarSort: SidebarSort {
        SidebarSort(rawValue: sortRaw) ?? .activity
    }

    /// Hidden rows show up only while the "Hidden workspaces" row is expanded.
    func isVisible(_ workspace: WorkspaceDescriptor) -> Bool {
        showHidden || !preferences.isHidden(workspace.id)
    }

    /// Persisted client-side set of hidden workspace ids (`paseo.sidebar.hiddenWorkspaces`).
    func isHiddenFromSidebar(_ workspace: WorkspaceDescriptor) -> Bool {
        preferences.isHidden(workspace.id)
    }

    func toggleHiddenFromSidebar(_ workspace: WorkspaceDescriptor) {
        preferences.toggleHidden(workspace.id)
    }

    /// Pinned workspaces, newest activity first.
    func pinnedWorkspaces(derivations: SidebarDerivations) -> [WorkspaceDescriptor] {
        sortedWorkspaces(
            session.workspaceDirectory.workspaces.filter {
                $0.isPinned && isVisible($0) && matchesLabelFilter($0)
            },
            derivations: derivations)
    }

    /// A workspace counts as running when the daemon's own bucket says so, or any agent in it
    /// is running — the same signal the row's dot uses.
    func isRunningWorkspace(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> Bool {
        if workspace.status == .running { return true }
        return agents(in: workspace, derivations: derivations).contains { $0.status == .running }
    }

    /// Workspaces per the sidebar sort, keys computed once each.
    ///
    /// The activity key comes from the shared `activityDates` table (built once per body
    /// evaluation) instead of being recomputed per comparison (P3/P5 finding #3).
    func sortedWorkspaces(
        _ workspaces: [WorkspaceDescriptor], derivations: SidebarDerivations
    ) -> [WorkspaceDescriptor] {
        let sorted: [WorkspaceDescriptor]
        switch sidebarSort {
        case .activity:
            sorted = workspaces
                .map { (workspace: $0, date: derivations.activityDates[$0.id]) }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                .map { $0.workspace }
        case .created:
            sorted = workspaces
                .map { (workspace: $0, date: createdDate($0)) }
                .sorted { left, right in
                    let l = left.date ?? .distantPast
                    let r = right.date ?? .distantPast
                    if l == r { return left.workspace.id > right.workspace.id }
                    return l > r
                }
                .map { $0.workspace }
        case .name:
            sorted = workspaces
                .map { (workspace: $0, title: workspaceTitle($0)) }
                .sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                .map { $0.workspace }
        }
        // Active first: running workspaces float to the head, stable otherwise.
        guard activeFirst else { return sorted }
        var running: [WorkspaceDescriptor] = []
        var rest: [WorkspaceDescriptor] = []
        for workspace in sorted {
            if isRunningWorkspace(workspace, derivations: derivations) {
                running.append(workspace)
            } else {
                rest.append(workspace)
            }
        }
        return running + rest
    }

    func createdDate(_ workspace: WorkspaceDescriptor) -> Date? {
        workspace.createdAt.flatMap(PaseoDate.parse)
    }

    /// Date buckets per DSH `date-groups`: today, yesterday, weekday names for the last six
    /// days, then one `earlier` bucket for anything a week or more old. Same visible/label-
    /// filtered set as the project grouping; each bucket is sorted and floated (active-first).
    func dateBuckets(derivations: SidebarDerivations) -> [SidebarDateBucket] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        var byBucket: [String: [WorkspaceDescriptor]] = ["today": [], "yesterday": [], "earlier": []]
        for offset in 2...6 { byBucket["day-\(offset)"] = [] }
        let visible = session.workspaceDirectory.workspaces.filter {
            !$0.isPinned && isVisible($0) && matchesLabelFilter($0)
        }
        for workspace in visible {
            let date = derivations.activityDates[workspace.id]
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
                id: "today", title: "Today",
                workspaces: sortedWorkspaces(byBucket["today"] ?? [], derivations: derivations)),
            SidebarDateBucket(
                id: "yesterday", title: "Yesterday",
                workspaces: sortedWorkspaces(byBucket["yesterday"] ?? [], derivations: derivations)),
        ]
        let symbols = calendar.weekdaySymbols
        for offset in 2...6 {
            let start = calendar.date(byAdding: .day, value: -offset, to: startOfToday) ?? startOfToday
            let weekdayIndex = calendar.component(.weekday, from: start) - 1
            let title = symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "Earlier"
            buckets.append(
                SidebarDateBucket(
                    id: "day-\(offset)", title: title,
                    workspaces: sortedWorkspaces(
                        byBucket["day-\(offset)"] ?? [], derivations: derivations)))
        }
        buckets.append(
            SidebarDateBucket(
                id: "earlier", title: "Earlier",
                workspaces: sortedWorkspaces(byBucket["earlier"] ?? [], derivations: derivations)))
        return buckets
    }

    // MARK: Date-group collapse (persisted, like projects)

    func isDateGroupCollapsed(_ id: String) -> Bool {
        preferences.isDateGroupCollapsed(id)
    }

    func toggleDateGroupCollapsed(_ id: String) {
        preferences.toggleDateGroupCollapsed(id)
    }

    // MARK: Manual unread marks (persisted locally, DSH `manual-unread`)

    func isManuallyUnread(_ workspace: WorkspaceDescriptor) -> Bool {
        preferences.isUnread(workspace.id)
    }

    func toggleManualUnread(_ workspace: WorkspaceDescriptor) {
        preferences.toggleUnread(workspace.id)
    }

    /// Cleared when the workspace is opened.
    func clearManualUnread(_ workspace: WorkspaceDescriptor) {
        preferences.clearUnread(workspace.id)
    }

    /// Workspaces within a project per the sidebar sort; projects ordered by their newest
    /// workspace (max of the sidebar sort key), name-sorted in "Name" mode. Pinned workspaces
    /// live in their own section and are excluded here, as are hidden rows.
    ///
    /// The group's sort date is computed once per group, not once per comparison (P3 — see
    /// `sortedWorkspaces`).
    func sortedGroups(
        _ groups: [WorkspaceGroup], derivations: SidebarDerivations
    ) -> [WorkspaceGroup] {
        groups
            .map { group in
                let workspaces = sortedWorkspaces(
                    group.workspaces.filter {
                        !$0.isPinned && isVisible($0) && matchesLabelFilter($0)
                    },
                    derivations: derivations)
                return (
                    group: WorkspaceGroup(project: group.project, workspaces: workspaces),
                    date: workspaces.compactMap {
                        groupSortDate($0, derivations: derivations)
                    }.max()
                )
            }
            .sorted { left, right in
                if sidebarSort == .name {
                    return left.group.project.projectDisplayName.localizedCaseInsensitiveCompare(
                        right.group.project.projectDisplayName) == .orderedAscending
                }
                let leftDate = left.date ?? .distantPast
                let rightDate = right.date ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.group.project.projectDisplayName.localizedCaseInsensitiveCompare(
                    right.group.project.projectDisplayName) == .orderedAscending
            }
            .map { $0.group }
    }

    func groupSortDate(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> Date? {
        sidebarSort == .created ? createdDate(workspace) : derivations.activityDates[workspace.id]
    }

    /// Last activity for a workspace: the newest of its agents' `updatedAt`/`lastUserMessageAt`,
    /// else the workspace's own `activityAt`/`lastUserMessageAt`/`createdAt`. Callers pass the
    /// precomputed agent list from `SidebarDerivations` (P5 finding #3).
    func activityDate(
        for workspace: WorkspaceDescriptor, agents: [AgentSnapshot]
    ) -> Date? {
        var best: Date?
        for agent in agents {
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
