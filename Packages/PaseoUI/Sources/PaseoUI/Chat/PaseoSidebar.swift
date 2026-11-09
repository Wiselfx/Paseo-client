#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The drawer: ClaudeUI's sidebar layout on `WorkspaceDirectory`'s project → workspace groups.
/// Agents are not listed here; they are the tabs inside a workspace. Projects are the collapsible
/// level (collapsed state persisted per project); workspace rows aggregate their agents' status and
/// open the most recently active agent. The footer holds the Settings avatar and the New workspace
/// capsule.
struct PaseoSidebar: View {
    let session: HostSession
    var selectedAgentId: String?
    var onSelectAgent: (String) -> Void
    var onNewAgent: (WorkspaceDescriptor) -> Void
    var onDisconnect: () -> Void

    @State private var sheet: PaseoSidebarSheet?
    @State private var showHidden = false
    @State private var renamingWorkspace: WorkspaceDescriptor?
    @State private var renamingProject: WorkspaceProjectDescriptor?
    @State private var projectPendingRemoval: WorkspaceProjectDescriptor?
    /// Set only when the daemon can't undo an archive: then a confirmation guards it instead.
    @State private var workspacePendingArchive: WorkspaceDescriptor?
    @State private var undoToast: (id: String, name: String)?
    @State private var undoToastToken = UUID()
    @State private var renameText = ""
    @State private var toast: String?
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.collapsedProjects") private var collapsedProjects = ""
    @AppStorage("paseo.sidebar.sort") private var sortRaw = SidebarSort.activity.rawValue
    @AppStorage("paseo.sidebar.showBranch") private var showBranch = true
    @AppStorage("paseo.sidebar.showDiffStats") private var showDiffStats = true
    @AppStorage("paseo.sidebar.showPRBadge") private var showPRBadge = true
    @AppStorage("paseo.sidebar.groupByProject") private var groupByProject = true
    @AppStorage("paseo.sidebar.hiddenWorkspaces") private var hiddenWorkspaces = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Row sort: last activity (default), creation date or name. Persisted per device.
    private enum SidebarSort: String, CaseIterable, Identifiable {
        case activity, created, name

        var id: String { rawValue }
        var title: String {
            switch self {
            case .activity: "Last activity"
            case .created: "Created"
            case .name: "Name"
            }
        }
    }

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo")
                    .font(typography.serif(27))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer()
                displayOptionsMenu
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navigation
                    directory
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ClaudePalette.sidebarBackground)
        .foregroundStyle(ClaudePalette.ink)
        .sheet(item: $sheet) { selection in
            switch selection {
            case .settings:
                PaseoSettingsView(session: session, onDisconnect: onDisconnect)
            case .schedules:
                ClaudeSchedulesView(session: session)
            case .history:
                ClaudeHistoryView(
                    session: session,
                    onClose: { sheet = nil },
                    onOpenAgent: { agentId in
                        sheet = nil
                        onSelectAgent(agentId)
                    })
            case .newWorkspace:
                ClaudeNewWorkspaceSheet(
                    session: session, defaultProjectId: selectedWorkspaceProjectId
                ) { agentId, message in
                    if let agentId {
                        onSelectAgent(agentId)
                    } else {
                        showToast(message ?? "Workspace created")
                    }
                }
            case .addProject:
                AddProjectSheet(session: session) { message in
                    showToast(message)
                }
            }
        }
        .alert(
            "Rename workspace",
            isPresented: Binding(
                get: { renamingWorkspace != nil },
                set: { if !$0 { renamingWorkspace = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingWorkspace = nil }
            Button("Rename") {
                let target = renamingWorkspace
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingWorkspace = nil
                guard let target, !title.isEmpty else { return }
                Task {
                    let renamed = await session.workspaceDirectory.renameWorkspace(
                        target.id, title: title)
                    if !renamed {
                        showToast(
                            session.workspaceDirectory.actionError ?? "Couldn't rename the workspace.")
                    }
                }
            }
        } message: {
            Text("Choose a short name for this workspace.")
        }
        .alert(
            "Rename project",
            isPresented: Binding(
                get: { renamingProject != nil },
                set: { if !$0 { renamingProject = nil } })
        ) {
            TextField("Folder name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingProject = nil }
            Button("Rename") {
                let target = renamingProject
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingProject = nil
                guard let target else { return }
                Task {
                    let renamed = await session.workspaceDirectory.renameProject(
                        target.projectId, to: title)
                    if !renamed {
                        showToast(
                            session.workspaceDirectory.actionError
                                ?? "Couldn't rename the project.")
                    }
                }
            }
        } message: {
            Text("Empty restores the folder name.")
        }
        .confirmationDialog(
            "Archive workspace?",
            isPresented: Binding(
                get: { workspacePendingArchive != nil },
                set: { if !$0 { workspacePendingArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let workspace = workspacePendingArchive else { return }
                workspacePendingArchive = nil
                archiveWorkspace(workspace)
            }
            Button("Cancel", role: .cancel) { workspacePendingArchive = nil }
        } message: {
            Text("Its agents and terminals stop. This host can't undo an archive.")
        }
        .confirmationDialog(
            "Remove project?",
            isPresented: Binding(
                get: { projectPendingRemoval != nil },
                set: { if !$0 { projectPendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let project = projectPendingRemoval else { return }
                projectPendingRemoval = nil
                Task {
                    let removed = await session.workspaceDirectory.removeProject(project.projectId)
                    showToast(
                        removed
                            ? "Project removed"
                            : (session.workspaceDirectory.actionError ?? "Couldn't remove the project."))
                }
            }
            Button("Cancel", role: .cancel) { projectPendingRemoval = nil }
        } message: {
            Text(
                "The project and its workspaces will be unregistered on this host. Files on disk will not be changed."
            )
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.top, 58)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let undoToast {
                HStack(spacing: 14) {
                    Text("Archived \(undoToast.name)")
                        .font(typography.sans(13, weight: .medium))
                        .lineLimit(1)
                    Button("Undo") {
                        let target = undoToast
                        self.undoToast = nil
                        undoToastToken = UUID()
                        Task {
                            let ok = await session.workspaceDirectory.undoArchive(target.id)
                            if !ok {
                                showToast(
                                    session.workspaceDirectory.actionError
                                        ?? "Couldn't undo the archive.")
                            }
                        }
                    }
                    .font(typography.sans(13, weight: .semibold))
                    .accessibilityLabel("Undo archive")
                }
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glassEffect(in: .capsule)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else { return }
            Task { await session.workspaceDirectory.refresh() }
        }
    }

    // MARK: Display options

    /// The "…" menu in the sidebar header: sort, row metadata and grouping; persisted in
    /// `@AppStorage("paseo.sidebar.*")`.
    private var displayOptionsMenu: some View {
        Menu {
            Picker(
                "Sort",
                selection: Binding(
                    get: { sidebarSort },
                    set: { sortRaw = $0.rawValue })
            ) {
                ForEach(SidebarSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            Divider()
            Toggle("Show branch", isOn: $showBranch)
            Toggle("Show diff stats", isOn: $showDiffStats)
            Toggle("Show PR badge", isOn: $showPRBadge)
            Toggle("Group by project", isOn: $groupByProject)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(ClaudePalette.tertiaryInk)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sidebar options")
    }

    // MARK: Navigation

    private var navigation: some View {
        VStack(spacing: 0) {
            navigationRow("Scheduled", symbol: "clock") { sheet = .schedules }
            navigationRow("History", symbol: "clock.arrow.2.circlepath") { sheet = .history }
        }
        .padding(.top, 4)
    }

    private func navigationRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 24)
                Text(title).font(typography.sans(18))
                Spacer(minLength: 0)
            }
            .frame(height: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Directory

    @ViewBuilder private var directory: some View {
        let groups = sortedGroups(session.workspaceDirectory.groups)
        let pinned = pinnedWorkspaces()
        if groupByProject {
            groupedDirectory(groups: groups, pinned: pinned)
        } else {
            flatDirectory(flat: flatWorkspaces, pinned: pinned)
        }
    }

    @ViewBuilder private func groupedDirectory(
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

    @ViewBuilder private func flatDirectory(
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

    @ViewBuilder private var trailingRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.workspaceDirectory.supportsProjectAdd {
                addProjectRow
            }
            if !hiddenWorkspacesSet.isEmpty {
                hiddenWorkspacesRow
            }
        }
    }

    private var hiddenWorkspacesRow: some View {
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

    private var emptyDirectoryState: some View {
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

    private var sidebarSort: SidebarSort {
        SidebarSort(rawValue: sortRaw) ?? .activity
    }

    private var hiddenWorkspacesSet: Set<String> {
        Set(hiddenWorkspaces.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    /// Hidden rows show up only while the "Hidden workspaces" row is expanded.
    private func isVisible(_ workspace: WorkspaceDescriptor) -> Bool {
        showHidden || !hiddenWorkspacesSet.contains(workspace.id)
    }

    /// Persisted client-side set of hidden workspace ids (`paseo.sidebar.hiddenWorkspaces`).
    private func isHiddenFromSidebar(_ workspace: WorkspaceDescriptor) -> Bool {
        hiddenWorkspacesSet.contains(workspace.id)
    }

    private func toggleHiddenFromSidebar(_ workspace: WorkspaceDescriptor) {
        var set = hiddenWorkspacesSet
        if set.contains(workspace.id) { set.remove(workspace.id) } else { set.insert(workspace.id) }
        hiddenWorkspaces = set.sorted().joined(separator: ",")
    }

    /// Pinned workspaces, newest activity first.
    private func pinnedWorkspaces() -> [WorkspaceDescriptor] {
        sortedWorkspaces(
            session.workspaceDirectory.workspaces.filter { $0.isPinned && isVisible($0) })
    }

    private func sortedWorkspaces(_ workspaces: [WorkspaceDescriptor]) -> [WorkspaceDescriptor] {
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

    private func createdDate(_ workspace: WorkspaceDescriptor) -> Date? {
        workspace.createdAt.flatMap(PaseoDate.parse)
    }

    private var flatWorkspaces: [WorkspaceDescriptor] {
        sortedWorkspaces(
            session.workspaceDirectory.workspaces.filter { !$0.isPinned && isVisible($0) })
    }

    /// Workspaces within a project per the sidebar sort; projects ordered by their newest
    /// workspace (max of the sidebar sort key), name-sorted in "Name" mode. Pinned workspaces
    /// live in their own section and are excluded here, as are hidden rows.
    private func sortedGroups(_ groups: [WorkspaceGroup]) -> [WorkspaceGroup] {
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

    private func groupSortDate(_ workspace: WorkspaceDescriptor) -> Date? {
        sidebarSort == .created ? createdDate(workspace) : activityDate(for: workspace)
    }

    private func activityDate(for workspace: WorkspaceDescriptor) -> Date? {
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

    /// A quiet row under the last project; opens the Add-project sheet.
    private var addProjectRow: some View {
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

    private func projectRow(_ group: WorkspaceGroup) -> some View {
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

    private func projectTitle(_ project: WorkspaceProjectDescriptor) -> String {
        project.projectCustomName ?? project.projectDisplayName
    }

    /// The group's workspaces are already ordered by activity, so the head is the most recent one.
    private func newAgent(in group: WorkspaceGroup) {
        guard let workspace = group.workspaces.first else {
            showToast("No workspace in this project yet — create one first.")
            return
        }
        Haptics.selection()
        onNewAgent(workspace)
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> some View {
        let rowAgents = agents(in: workspace)
        let selected = rowAgents.contains { $0.id == selectedAgentId }
        let attention = rowAgents.contains { $0.requiresAttention == true }
        return Button {
            openWorkspace(workspace)
        } label: {
            HStack(spacing: 8) {
                PaseoStatusDot(kind: workspaceStatusKind(workspace, agents: rowAgents))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspaceTitle(workspace))
                        .font(typography.sans(16, weight: .medium))
                        .lineLimit(1)
                    metaRow(workspace)
                }
                Spacer(minLength: 0)
                if attention {
                    PaseoStatusDot(kind: .unread)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background(selected ? ClaudePalette.chip : Color.clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(attention ? "Needs attention" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("New agent here", systemImage: "plus") { onNewAgent(workspace) }
            Button("Rename workspace", systemImage: "pencil") {
                renameText = workspace.title ?? workspace.name
                renamingWorkspace = workspace
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = workspace.cwd
                showToast("Path copied")
            }
            if let branch = workspace.branch {
                Button("Copy branch name", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = branch
                    showToast("Branch name copied")
                }
            }
            if session.workspaceDirectory.supportsWorkspacePinning {
                Button(
                    workspace.isPinned ? "Unpin" : "Pin",
                    systemImage: workspace.isPinned ? "pin.slash" : "pin"
                ) {
                    Task {
                        let ok = await session.workspaceDirectory.setPinned(
                            workspace.id, !workspace.isPinned)
                        if !ok {
                            showToast(
                                session.workspaceDirectory.actionError
                                    ?? "Couldn't change the pin.")
                        }
                    }
                }
            }
            Button(isHiddenFromSidebar(workspace) ? "Unhide from sidebar" : "Hide from sidebar", systemImage: isHiddenFromSidebar(workspace) ? "eye" : "eye.slash") {
                Haptics.selection()
                toggleHiddenFromSidebar(workspace)
            }
            Button("Archive workspace", systemImage: "archivebox", role: .destructive) {
                if session.workspaceDirectory.supportsWorkspaceArchiveUndo {
                    archiveWorkspace(workspace)
                } else {
                    workspacePendingArchive = workspace
                }
            }
        }
    }

    /// Tapping a workspace opens its most recently active agent; the other agents are the header's
    /// tab chips.
    private func openWorkspace(_ workspace: WorkspaceDescriptor) {
        Haptics.selection()
        guard let target = agents(in: workspace).first else {
            showToast("No agents in this workspace yet — long-press to create one.")
            return
        }
        onSelectAgent(target.id)
    }

    private func agents(in workspace: WorkspaceDescriptor) -> [AgentSnapshot] {
        session.agents.filter { $0.workspaceId == workspace.id }
    }

    /// One line: the workspace title, or the branch when there is no title.
    private func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    @ViewBuilder private func metaRow(_ workspace: WorkspaceDescriptor) -> some View {
        HStack(spacing: 4) {
            if showBranch {
                Text(workspace.branch ?? workspaceKindLabel(workspace))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
            }
            if showDiffStats, let stat = workspace.diffStat, stat.additions > 0 || stat.deletions > 0 {
                if showBranch { Text("·").foregroundStyle(ClaudePalette.captionInk) }
                if stat.additions > 0 {
                    Text("+\(stat.additions)")
                        .foregroundStyle(ClaudePalette.successInk.opacity(0.75))
                }
                if stat.deletions > 0 {
                    Text("−\(stat.deletions)")
                        .foregroundStyle(ClaudePalette.failureInk.opacity(0.75))
                }
            }
            if let stamp = activityDate(for: workspace) {
                if showBranch || hasVisibleDiffStat(workspace) {
                    Text("·").foregroundStyle(ClaudePalette.captionInk)
                }
                Text(relativeAge(stamp))
                    .foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 6)
            if showPRBadge, let pullRequest = pullRequest(workspace), let number = pullRequest.number {
                Text("#\(number)")
                    .font(typography.sans(11, weight: .semibold))
                    .foregroundStyle(pullRequestTint(workspace))
            }
            if let dots = scriptDots(workspace), !dots.isEmpty {
                HStack(spacing: 3) {
                    ForEach(0..<dots.count, id: \.self) { index in
                        Circle().fill(dots[index]).frame(width: 5, height: 5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(scriptDotsLabel(workspace, count: dots.count))
            }
        }
        .font(typography.sans(12))
        .lineLimit(1)
    }

    private func hasVisibleDiffStat(_ workspace: WorkspaceDescriptor) -> Bool {
        guard showDiffStats, let stat = workspace.diffStat else { return false }
        return stat.additions > 0 || stat.deletions > 0
    }

    /// The descriptor carries the PR summary (`githubRuntime.pullRequest`); per-checkout PR state
    /// (GitExtras) would need a checkout per row, which we don't want on a hot list.
    private func pullRequest(_ workspace: WorkspaceDescriptor) -> WorkspaceGitHubRuntime.WorkspacePullRequest? {
        workspace.githubRuntime?.pullRequest
    }

    private func pullRequestTint(_ workspace: WorkspaceDescriptor) -> Color {
        guard let pr = pullRequest(workspace) else { return ClaudePalette.secondaryInk }
        if pr.isMerged { return ClaudePalette.unread }
        if pr.isDraft == true { return ClaudePalette.tertiaryInk }
        switch pr.state.lowercased() {
        case "open": return ClaudePalette.successInk
        case "closed": return ClaudePalette.failureInk
        default: return ClaudePalette.secondaryInk
        }
    }

    /// One dot per script in trouble: green running, red when it exited non-zero. Live state from
    /// the terminals store when it has it, else the pushed descriptor payload.
    private func scriptDots(_ workspace: WorkspaceDescriptor) -> [Color] {
        let storeScripts = session.terminals.scripts(in: workspace.id)
        let scripts = storeScripts.isEmpty ? workspace.scripts : storeScripts
        var dots: [Color] = []
        for script in scripts {
            if script.lifecycle == .running {
                dots.append(ClaudePalette.successInk)
            } else if let code = script.exitCode, code != 0 {
                dots.append(ClaudePalette.failureInk)
            }
        }
        return Array(dots.prefix(3))
    }

    private func scriptDotsLabel(_ workspace: WorkspaceDescriptor, count: Int) -> String {
        let storeScripts = session.terminals.scripts(in: workspace.id)
        let scripts = storeScripts.isEmpty ? workspace.scripts : storeScripts
        let running = scripts.filter { $0.lifecycle == .running }.count
        let crashed = scripts.filter { script in
            script.lifecycle != .running && (script.exitCode ?? 0) != 0
        }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if crashed > 0 { parts.append("\(crashed) exited") }
        return "Scripts: " + (parts.isEmpty ? "\(count)" : parts.joined(separator: ", "))
    }

    /// "now", "5m", "3h", "2d", "4mo" — compact ages for the meta line.
    private func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        return "\(days / 30)mo"
    }

    // MARK: Status

    /// Leading dot aggregated from the workspace's agents: permission → needs input, error →
    /// failed, running → working, finished-but-unseen → unread. Falls back to the workspace's own
    /// status bucket when no agent outranks it.
    private func workspaceStatusKind(
        _ workspace: WorkspaceDescriptor, agents: [AgentSnapshot]
    ) -> PaseoStatusDot.Kind {
        if agents.contains(where: { $0.attention == .permission }) { return .needsInput }
        if agents.contains(where: { $0.attention == .error || $0.status == .error }) { return .failed }
        if agents.contains(where: { $0.status == .running }) { return .running }
        if agents.contains(where: { $0.attention == .finished }) { return .unread }
        return statusKind(workspace.status)
    }

    private func statusKind(_ status: WorkspaceStatusBucket) -> PaseoStatusDot.Kind {
        switch status {
        case .needsInput, .attention: .needsInput
        case .failed: .failed
        case .running: .running
        case .done: .done
        case .unknown: .idle
        }
    }

    private func workspaceKindLabel(_ workspace: WorkspaceDescriptor) -> String {
        switch workspace.workspaceKind {
        case .worktree: "Worktree"
        case .checkout, .localCheckout: "Checkout"
        case .directory: "Project root"
        case .unknown: "Workspace"
        }
    }

    // MARK: Collapse state

    private var collapsedProjectsSet: Set<String> {
        Set(collapsedProjects.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func isCollapsed(_ projectId: String) -> Bool {
        collapsedProjectsSet.contains(projectId)
    }

    private func toggleCollapsed(_ projectId: String) {
        var collapsed = collapsedProjectsSet
        if collapsed.contains(projectId) {
            collapsed.remove(projectId)
        } else {
            collapsed.insert(projectId)
        }
        collapsedProjects = collapsed.sorted().joined(separator: ",")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.selection()
                sheet = .settings
            } label: {
                Text(initial)
                    .font(typography.serif(18, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Spacer(minLength: 0)

            Button {
                Haptics.selection()
                if session.workspaceDirectory.supportsWorkspaceCreate {
                    sheet = .newWorkspace
                } else {
                    showToast("This daemon cannot create workspaces.")
                }
            } label: {
                Label("New workspace", systemImage: "plus")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.background)
                    .padding(.horizontal, 17)
                    .frame(height: 44)
                    .background(ClaudePalette.ink, in: .capsule)
                    .opacity(session.workspaceDirectory.supportsWorkspaceCreate ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New workspace")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "P" }
        return String(first).uppercased()
    }

    /// The project whose workspace is showing the selected agent, for the new-workspace sheet's
    /// default picker selection.
    private var selectedWorkspaceProjectId: String? {
        guard
            let selectedAgentId,
            let agent = session.agents.first(where: { $0.id == selectedAgentId }),
            let workspaceId = agent.workspaceId
        else { return nil }
        return session.workspaceDirectory.workspace(id: workspaceId)?.projectId
    }

    /// Archives a workspace (confirmed first when the host can't undo; else the undo toast is the
    /// safety net) and surfaces the outcome as a bottom toast with an Undo for ~5 s.
    private func archiveWorkspace(_ workspace: WorkspaceDescriptor) {
        let supportsUndo = session.workspaceDirectory.supportsWorkspaceArchiveUndo
        Task {
            let archived = await session.workspaceDirectory.archiveWorkspaceWithUndo(workspace.id)
            guard archived else {
                showToast(
                    session.workspaceDirectory.actionError ?? "Couldn't archive the workspace.")
                return
            }
            if supportsUndo {
                showArchiveToast(for: workspace)
            } else {
                showToast("Archived \(workspaceTitle(workspace))")
            }
        }
    }

    private func showArchiveToast(for workspace: WorkspaceDescriptor) {
        let name = workspaceTitle(workspace)
        let token = UUID()
        undoToastToken = token
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            undoToast = (workspace.id, name)
        }
        Haptics.selection()
        UIAccessibility.post(notification: .announcement, argument: "Workspace archived: \(name). Undo is available.")
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard undoToastToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                undoToast = nil
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

/// The height roll for a project's workspace rows: 200 ms, ease-out, measured naturally.
private struct SidebarRoll<Content: View>: View {
    let expanded: Bool
    @ViewBuilder var content: () -> Content

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: SidebarRollHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(SidebarRollHeightKey.self) { contentHeight = $0 }
            .frame(height: expanded ? contentHeight : 0, alignment: .top)
            .clipped()
            .opacity(expanded ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move), value: expanded)
    }
}

private struct SidebarRollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum PaseoSidebarSheet: Identifiable {
    case settings
    case schedules
    case history
    case newWorkspace
    case addProject

    var id: String {
        switch self {
        case .settings: "settings"
        case .schedules: "schedules"
        case .history: "history"
        case .newWorkspace: "newWorkspace"
        case .addProject: "addProject"
        }
    }
}


/// The full new-workspace sheet in ClaudeUI's sheet chrome: pick a project (defaulting to the
/// selected workspace's project), an optional name, isolation (Local vs New worktree), the base
/// branch to fork from (free text, current branch prefilled — the store exposes branch
/// suggestions only per checkout, which this sheet does not have), and an optional first prompt,
/// which creates an agent in the new workspace right away with the catalogue's provider defaults.
private struct ClaudeNewWorkspaceSheet: View {
    let session: HostSession
    let defaultProjectId: String?
    /// `agentId` when a first prompt produced an agent; `message` carries a toast line for
    /// partial failures (e.g. the workspace was created but the agent couldn't start).
    var onCreated: (String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projectId: String?
    @State private var name = ""
    @State private var isolation: Isolation = .worktree
    @State private var baseBranchText = ""
    @State private var prompt = ""
    @State private var busyStep: BusyStep?
    private let typography = ClaudeTypography()

    enum Isolation: String, CaseIterable, Identifiable {
        case local
        case worktree

        var id: String { rawValue }

        var title: String {
            switch self {
            case .local: "Local"
            case .worktree: "New worktree"
            }
        }
    }

    enum BusyStep {
        case workspace
        case agent

        var label: String {
            switch self {
            case .workspace: "Creating workspace…"
            case .agent: "Creating agent…"
            }
        }
    }

    private var directory: WorkspaceDirectory { session.workspaceDirectory }
    private var catalog: AgentControlStore { session.agentControl }
    private var projects: [WorkspaceProjectDescriptor] { directory.projects }

    private var selectedProjectId: String {
        projectId ?? defaultProjectId ?? projects.first?.projectId ?? ""
    }

    private var selectedProject: WorkspaceProjectDescriptor? {
        projects.first { $0.projectId == selectedProjectId }
    }

    /// The branch a worktree forks from: the project's local (non-worktree) checkout branch,
    /// else any branch the directory carries, else "main". Used to prefill the base-branch field.
    private var currentBranch: String {
        let projectId = selectedProject?.projectId
        let workspaces = directory.workspaces.filter { $0.projectId == projectId }
        if let branch = workspaces.first(where: { $0.workspaceKind != .worktree && $0.branch != nil })?
            .branch
        {
            return branch
        }
        return workspaces.compactMap(\.branch).first ?? "main"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        guard busyStep == nil, selectedProject != nil else { return false }
        if isolation == .worktree { return directory.supportsWorkspaceCreate }
        return true
    }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "New workspace", close: { dismiss() })
            ScrollView {
                VStack(spacing: 12) {
                    RowGroup {
                        HStack(spacing: 12) {
                            Text("Project")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            Picker(
                                "Project",
                                selection: Binding(
                                    get: { selectedProjectId },
                                    set: { projectId = $0 })
                            ) {
                                ForEach(projects) { project in
                                    Text(
                                        project.projectCustomName ?? project.projectDisplayName
                                    )
                                    .tag(project.projectId)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(typography.sans(16))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        RowDivider()
                        HStack(spacing: 12) {
                            Text("Name")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            TextField("Optional", text: $name)
                                .font(typography.sans(17))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    isolationSection
                    if isolation == .worktree {
                        baseBranchSection
                    }
                    promptSection
                    if let error = directory.actionError {
                        Text(error)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if let error = catalog.actionError {
                        Text(error)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    createButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .onAppear {
            baseBranchText = currentBranch
            if !directory.supportsWorkspaceCreate { isolation = .local }
        }
        .onChange(of: selectedProjectId) { _, _ in
            baseBranchText = currentBranch
        }
    }

    private var isolationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Isolation")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            HStack(spacing: 2) {
                ForEach(Isolation.allCases) { option in
                    Button {
                        guard option == .local || directory.supportsWorkspaceCreate else { return }
                        Haptics.selection()
                        isolation = option
                    } label: {
                        Text(option.title)
                            .font(typography.sans(14, weight: isolation == option ? .medium : .regular))
                            .foregroundStyle(
                                isolation == option ? ClaudePalette.background : ClaudePalette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                isolation == option ? ClaudePalette.ink : Color.clear, in: .capsule)
                            .opacity(
                                option == .worktree && !directory.supportsWorkspaceCreate ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(option == .worktree && !directory.supportsWorkspaceCreate)
                    .accessibilityLabel(option.title)
                }
            }
            .padding(3)
            .background(ClaudePalette.chip, in: .capsule)
            if !directory.supportsWorkspaceCreate {
                Text("This daemon cannot create worktrees; new sessions open the project root.")
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.captionInk)
                    .padding(.leading, 4)
            }
        }
    }

    private var baseBranchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Branch off")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            RowGroup {
                HStack(spacing: 12) {
                    Text("Branch")
                        .font(typography.sans(17))
                    Spacer(minLength: 8)
                    TextField(
                        "", text: $baseBranchText,
                        prompt: Text("main").foregroundStyle(ClaudePalette.secondary)
                    )
                    .font(typography.mono(13))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
            }
            Text("The new worktree forks from this branch. The daemon reports no branch list here; type one.")
                .font(typography.sans(12))
                .foregroundStyle(ClaudePalette.captionInk)
                .padding(.horizontal, 4)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("First prompt")
                .font(typography.sans(13, weight: .medium))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.leading, 4)
            RowGroup {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "", text: $prompt,
                        prompt: Text("What should the agent do?").foregroundStyle(ClaudePalette.secondary),
                        axis: .vertical
                    )
                    .font(typography.sans(16))
                    .lineLimit(1...4)
                    Text("Creates an agent right away with this host's default provider, model and mode.")
                        .font(typography.sans(11))
                        .foregroundStyle(ClaudePalette.captionInk)
                }
                .padding(12)
            }
        }
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 8) {
                if busyStep != nil {
                    ProgressView().controlSize(.small).tint(ClaudePalette.background)
                }
                Text(busyStep?.label ?? "Create workspace")
                    .font(typography.sans(16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(ClaudePalette.background)
            .background(ClaudePalette.ink, in: .capsule)
            .opacity(canCreate ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canCreate)
        .padding(.top, 4)
        .accessibilityIdentifier("newWorkspace.create")
    }

    private func create() {
        guard let project = selectedProject else { return }
        let title = trimmedName.isEmpty ? nil : trimmedName
        let prompt = trimmedPrompt
        let source: NewWorkspaceSource
        switch isolation {
        case .local:
            source = .local
        case .worktree:
            let typed = baseBranchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = typed.isEmpty ? currentBranch : typed
            let baseRef = base.hasPrefix("refs/") ? base : "refs/heads/\(base)"
            let branchName = branchSlug(trimmedName) ?? "workspace-\(Int(Date().timeIntervalSince1970))"
            source = .branchOff(baseRef: baseRef, branchName: branchName, worktreeSlug: branchName)
        }
        busyStep = .workspace
        Task {
            let created = await directory.createWorkspace(in: project, source: source, title: title)
            guard let workspace = created else {
                busyStep = nil
                return
            }
            var agentId: String?
            var message: String?
            if !prompt.isEmpty {
                busyStep = .agent
                agentId = await createAgent(in: workspace, prompt: prompt)
                if agentId == nil {
                    message = catalog.actionError ?? "Workspace created — but the agent couldn't start."
                }
            }
            await session.refreshAgents()
            onCreated(agentId, message)
            dismiss()
        }
    }

    /// Provider defaults as the new-agent sheet computes them: the first ready provider, its
    /// default model, thinking level and mode.
    private func createAgent(in workspace: WorkspaceDescriptor, prompt: String) async -> String? {
        let needsLoad: Bool
        switch catalog.phase {
        case .idle, .failed: needsLoad = true
        case .loading, .ready: needsLoad = catalog.providers.isEmpty
        }
        if needsLoad { await catalog.loadCatalog() }
        guard let providerId = catalog.readyProviders.first?.provider else {
            return nil
        }
        guard let model = catalog.defaultModel(forProvider: providerId) else {
            return nil
        }
        let thinking = model.defaultThinkingOptionId
        let mode =
            catalog.provider(providerId)?.defaultModeId
            ?? catalog.modes(forProvider: providerId).first?.id
        return await catalog.createAgent(
            cwd: workspace.cwd, workspaceId: workspace.id, provider: providerId, model: model.id,
            modeId: mode, thinkingOptionId: thinking, prompt: prompt)
    }

    /// Lowercase, non-alphanumerics collapsed to single dashes, trimmed; nil when nothing is left.
    private func branchSlug(_ raw: String) -> String? {
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        var slug = String(mapped)
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if slug.isEmpty { return nil }
        return String(slug.prefix(40))
    }
}

/// 6 pt dot: breathing while running, yellow for input, blue for unread, hollow for idle.
struct PaseoStatusDot: View {
    enum Kind: Equatable { case running, needsInput, failed, done, unread, idle }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Group {
            switch kind {
            case .running:
                Circle().fill(ClaudePalette.secondaryInk).frame(width: 6, height: 6)
                    .opacity(breathing ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: breathing)
                    .onAppear { breathing = true }
            case .needsInput: Circle().fill(ClaudePalette.warning).frame(width: 6, height: 6)
            case .failed: Circle().fill(ClaudePalette.failureInk).frame(width: 6, height: 6)
            case .done: Circle().fill(ClaudePalette.successInk).frame(width: 6, height: 6)
            case .unread: Circle().fill(ClaudePalette.unread).frame(width: 6, height: 6)
            case .idle: Circle().strokeBorder(ClaudePalette.captionInk, lineWidth: 1).frame(width: 6, height: 6)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
#endif
