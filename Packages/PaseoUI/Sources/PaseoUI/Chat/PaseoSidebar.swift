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
    @State private var renamingWorkspace: WorkspaceDescriptor?
    @State private var workspacePendingArchive: WorkspaceDescriptor?
    @State private var projectPendingRemoval: WorkspaceProjectDescriptor?
    @State private var renameText = ""
    @State private var toast: String?
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.collapsedProjects") private var collapsedProjects = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo")
                    .font(typography.serif(27))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer()
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
                ClaudeSidebarSettingsSheet(session: session, onDisconnect: onDisconnect)
            case .comingSoon(let title):
                ClaudeSidebarComingSoonSheet(title: title)
            case .newWorkspace:
                ClaudeNewWorkspaceSheet(
                    session: session, defaultProjectId: selectedWorkspaceProjectId
                ) {
                    showToast("Workspace created")
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
                Task {
                    let archived = await session.workspaceDirectory.archiveWorkspace(workspace.id)
                    if !archived {
                        showToast(
                            session.workspaceDirectory.actionError
                                ?? "Couldn't archive the workspace.")
                    }
                }
            }
            Button("Cancel", role: .cancel) { workspacePendingArchive = nil }
        } message: {
            Text(archiveMessage(for: workspacePendingArchive))
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
        .onAppear {
            guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else { return }
            Task { await session.workspaceDirectory.refresh() }
        }
    }

    // MARK: Navigation

    private var navigation: some View {
        VStack(spacing: 0) {
            navigationRow("Scheduled", symbol: "clock") { sheet = .comingSoon("Scheduled") }
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
        if groups.isEmpty {
            let error = session.workspaceDirectory.error
            Text(
                session.workspaceDirectory.isLoading
                    ? "Loading workspaces…"
                    : (error ?? "No workspaces on this host yet.")
            )
            .font(typography.sans(14))
            .foregroundStyle(error == nil ? ClaudePalette.secondaryInk : ClaudePalette.failureInk)
            .padding(.vertical, 24)
        } else {
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
        }
    }

    /// Workspaces within a project, newest activity first; projects ordered by their newest
    /// workspace. Activity is the max of the workspace's agents' `updatedAt`/`lastUserMessageAt`,
    /// falling back to the workspace's own `activityAt` → `lastUserMessageAt` → `createdAt`.
    private func sortedGroups(_ groups: [WorkspaceGroup]) -> [WorkspaceGroup] {
        groups
            .map { group in
                WorkspaceGroup(
                    project: group.project,
                    workspaces: group.workspaces.sorted {
                        (activityDate(for: $0) ?? .distantPast) > (activityDate(for: $1) ?? .distantPast)
                    })
            }
            .sorted { left, right in
                let leftDate = left.workspaces.compactMap { activityDate(for: $0) }.max() ?? .distantPast
                let rightDate = right.workspaces.compactMap { activityDate(for: $0) }.max() ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return left.project.projectDisplayName.localizedCaseInsensitiveCompare(
                    right.project.projectDisplayName) == .orderedAscending
            }
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
                    Text(metaLine(workspace))
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
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
            Button("Archive workspace", systemImage: "archivebox", role: .destructive) {
                workspacePendingArchive = workspace
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

    private func metaLine(_ workspace: WorkspaceDescriptor) -> String {
        let branch = workspace.branch ?? workspaceKindLabel(workspace)
        guard let stamp = activityDate(for: workspace) else { return branch }
        return "\(branch) · \(relativeAge(stamp))"
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
        HStack(spacing: 12) {
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

            Spacer(minLength: 0)
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

    private func archiveMessage(for workspace: WorkspaceDescriptor?) -> String {
        guard let workspace else { return "" }
        if agents(in: workspace).contains(where: { $0.status == .running }) {
            return "This agent is still running. Archiving it will stop the agent."
        }
        return "The workspace and its agents will be archived."
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
    case comingSoon(String)
    case newWorkspace

    var id: String {
        switch self {
        case .settings: "settings"
        case .comingSoon(let title): "coming.\(title)"
        case .newWorkspace: "newWorkspace"
        }
    }
}

/// The screens that do not exist yet, in ClaudeUI's sheet chrome.
private struct ClaudeSidebarComingSoonSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: title, close: { dismiss() })
            Spacer()
            Text("Coming soon")
                .font(typography.serif(24, relativeTo: .title2))
                .foregroundStyle(ClaudePalette.ink)
            Text("This screen isn't built yet.")
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Spacer()
        }
        .background(ClaudePalette.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }
}

/// Appearance and the optional name the home greeting uses. The rest of Settings is still to come.
private struct ClaudeSidebarSettingsSheet: View {
    let session: HostSession
    let onDisconnect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PaseoSettingsKeys.appearance) private var appearance = ClaudeAppearance.system.rawValue
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @State private var confirmDisconnect = false
    private let typography = ClaudeTypography()

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(title: "Settings", close: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Appearance")
                    RowGroup {
                        HStack {
                            Text("Theme")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            Picker("Theme", selection: $appearance) {
                                ForEach(ClaudeAppearance.allCases, id: \.self) { choice in
                                    Text(choice.rawValue).tag(choice.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(typography.sans(16))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    sectionTitle("Your name")
                    RowGroup {
                        HStack {
                            Text("Name")
                                .font(typography.sans(17))
                            Spacer(minLength: 8)
                            TextField("Your name", text: $name)
                                .font(typography.sans(17))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                    }
                    Text("Used in the greeting on the home screen.")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.captionInk)
                    Text("Scheduled and Workspaces settings are coming soon.")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(.top, 8)
                    hostSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
        .confirmationDialog(
            "Disconnect from this host?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                onDisconnect()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The connection to the daemon will be closed. Your settings are kept.")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(typography.sans(13, weight: .medium))
            .foregroundStyle(ClaudePalette.secondaryInk)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    /// The host this app is talking to: server id and a connection dot, plus a destructive
    /// Disconnect.
    @ViewBuilder private var hostSection: some View {
        sectionTitle("Host")
        RowGroup {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection")
                        .font(typography.sans(17))
                    Text(session.serverInfo?.hostname ?? "Paseo daemon")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    PaseoStatusDot(kind: connectionKind(session.connection))
                    Text(connectionLabel(session.connection))
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            RowDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Server ID")
                    .font(typography.sans(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                Text(session.serverInfo?.serverId ?? "Not connected")
                    .font(typography.mono(13, relativeTo: .footnote))
                    .foregroundStyle(ClaudePalette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        RowGroup {
            Button {
                confirmDisconnect = true
            } label: {
                HStack {
                    Text("Disconnect")
                        .font(typography.sans(17))
                        .foregroundStyle(ClaudePalette.failureInk)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Disconnect")
        }
    }
}

/// The minimal new-workspace sheet in ClaudeUI's sheet chrome: pick a project (defaulting to the
/// selected workspace's project), an optional name, and create a worktree off the project's current
/// branch.
private struct ClaudeNewWorkspaceSheet: View {
    let session: HostSession
    let defaultProjectId: String?
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projectId: String?
    @State private var name = ""
    private let typography = ClaudeTypography()

    private var directory: WorkspaceDirectory { session.workspaceDirectory }
    private var projects: [WorkspaceProjectDescriptor] { directory.projects }

    private var selectedProjectId: String {
        projectId ?? defaultProjectId ?? projects.first?.projectId ?? ""
    }

    private var selectedProject: WorkspaceProjectDescriptor? {
        projects.first { $0.projectId == selectedProjectId }
    }

    /// The branch the new worktree forks from: the project's local (non-worktree) checkout branch,
    /// else any branch in the project, else "main".
    private var baseBranch: String {
        let projectId = selectedProject?.projectId
        let workspaces = directory.workspaces.filter { $0.projectId == projectId }
        if let branch = workspaces.first(where: { $0.workspaceKind != .worktree && $0.branch != nil })?
            .branch
        {
            return branch
        }
        return workspaces.compactMap(\.branch).first ?? "main"
    }

    private var canCreate: Bool {
        directory.supportsWorkspaceCreate && !directory.isCreatingWorkspace && selectedProject != nil
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
                    if directory.supportsWorkspaceCreate {
                        Text("Creates a git worktree off \(baseBranch).")
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.captionInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    } else {
                        Text("This daemon cannot create workspaces.")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if let error = directory.actionError {
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private var createButton: some View {
        Button {
            create()
        } label: {
            HStack(spacing: 8) {
                if directory.isCreatingWorkspace {
                    ProgressView().controlSize(.small).tint(ClaudePalette.background)
                }
                Text(directory.isCreatingWorkspace ? "Creating…" : "Create workspace")
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
        .accessibilityIdentifier("newWorkspace.create")
    }

    private func create() {
        guard let project = selectedProject else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchName = branchSlug(trimmed) ?? "workspace-\(Int(Date().timeIntervalSince1970))"
        let baseRef = baseBranch.hasPrefix("refs/") ? baseBranch : "refs/heads/\(baseBranch)"
        let title = trimmed.isEmpty ? nil : trimmed
        Task {
            let created = await directory.createWorkspace(
                in: project,
                source: .branchOff(baseRef: baseRef, branchName: branchName, worktreeSlug: branchName),
                title: title)
            if created != nil {
                onCreated()
                dismiss()
            }
        }
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

/// Connection state as a status dot and a short label, shared by the Settings sheet's Host section.
private func connectionKind(_ state: ConnectionState) -> PaseoStatusDot.Kind {
    switch state {
    case .connected: .done
    case .reconnecting, .connecting: .running
    case .failed: .failed
    case .idle: .idle
    }
}

private func connectionLabel(_ state: ConnectionState) -> String {
    switch state {
    case .connected: "Connected"
    case .connecting: "Connecting…"
    case .reconnecting(let attempt, _): "Reconnecting (attempt \(attempt))"
    case .failed: "Disconnected"
    case .idle: "Not connected"
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
