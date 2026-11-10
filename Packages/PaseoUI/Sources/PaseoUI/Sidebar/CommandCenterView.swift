#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// M9: the command center. A full-height search sheet over the sidebar, in the DSH palette
/// style: one field, grouped results — Agents (live + archived), Workspaces, Projects, Files in
/// the open workspace, and Actions. Return opens the first/selected result; arrow keys on a
/// hardware keyboard move the highlight; empty field shows recents.
struct CommandCenterSheet: View {
    let session: HostSession

    /// Opens the agent in the chat (the sidebar dismisses this sheet and selects it).
    let onOpenAgent: (String) -> Void
    /// Starts an agent in the given workspace (the shell shows the New agent sheet).
    let onNewAgent: (WorkspaceDescriptor) -> Void
    /// Opens the New workspace sheet (replacing this sheet).
    let onNewWorkspace: () -> Void
    /// Opens Settings (replacing this sheet).
    let onOpenSettings: () -> Void
    /// Toggles the right-side workspace panel; nil hides the Toggle panel action.
    let onTogglePanel: (() -> Void)?
    /// Opens the Import session sheet; nil hides the action when the daemon lacks the feature.
    var onImportSession: (() -> Void)? = nil
    let onShowToast: (String) -> Void
    let onClose: () -> Void
    /// The agent open in the chat, if any; the Files group searches its workspace.
    let selectedAgentId: String?

    @Environment(\.hostSwitch) private var hostSwitch

    @State private var query = ""
    @FocusState private var fieldFocused: Bool
    @State private var selectedIndex = 0
    @State private var mentionIndex = MentionIndex()
    @State private var fileViewer: FileViewerTarget?
    /// The "Switch host…" row expands in place with the saved hosts.
    @State private var hostExpanded = false

    // MARK: Result model

    enum ResultKind { case agent, workspace, project, file, action, hostEntry }

    /// One flattened row in the results list; carries everything needed to render and act.
    struct Result: Identifiable {
        let id: String
        let kind: ResultKind
        let title: String
        let subtitle: String?
        let symbol: String?
        let dot: PaseoStatusDot.Kind?
        let archived: Bool
        let agent: AgentSnapshot?
        let workspace: WorkspaceDescriptor?
        let fileRow: MentionIndexRow?
        let action: CommandAction?
        let hostEntry: HostSwitchEntry?
        let keywords: String
    }

    enum CommandAction: String, CaseIterable {
        case newAgent
        case newWorkspace
        case importSession
        case openSettings
        case togglePanel
        case switchHost

        var title: String {
            switch self {
            case .newAgent: "New agent"
            case .newWorkspace: "New workspace"
            case .importSession: "Import session"
            case .openSettings: "Open settings"
            case .togglePanel: "Toggle panel"
            case .switchHost: "Switch host…"
            }
        }

        var symbol: String {
            switch self {
            case .newAgent: "square.and.pencil"
            case .newWorkspace: "plus"
            case .importSession: "square.and.arrow.down"
            case .openSettings: "gearshape"
            case .togglePanel: "sidebar.right"
            case .switchHost: "desktopcomputer"
            }
        }

        var keywords: String {
            switch self {
            case .newAgent: "create start run"
            case .newWorkspace: "create add worktree"
            case .importSession: "existing cli terminal session resume host"
            case .openSettings: "preferences gear"
            case .togglePanel: "sidebar right files changes terminal"
            case .switchHost: "daemon saved server machine"
            }
        }

        /// Scoring against the typed query; nil hides the row.
        func matchScore(_ q: String) -> Int? {
            if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 100 }
            if title.range(of: q, options: .caseInsensitive) != nil { return 60 }
            if keywords.range(of: q, options: .caseInsensitive) != nil { return 30 }
            return nil
        }
    }

    // MARK: Sheet chrome

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            resultsList
        }
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .sheet(item: $fileViewer) { target in
            WorkspaceFileViewer(
                checkout: target.checkout, relPath: target.relPath,
                onBack: { fileViewer = nil }, backLabel: "Search")
        }
        .task {
            fieldFocused = true
            if session.agentLifecycle.phase == .idle {
                await session.agentLifecycle.load()
            }
            if let workspace = openWorkspace {
                let checkout = session.checkout(for: workspace)
                await mentionIndex.build(using: checkout.files)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Search")
                .font(.paseo(.title, weight: .semibold))
            HStack {
                Button {
                    Haptics.selection()
                    onClose()
                } label: {
                    Image(systemName: "xmark").font(.glyph(.large, weight: .light))
                        .frame(width: 42, height: 42)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .accessibilityIdentifier("search.header")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
            TextField("Search agents, workspaces, files, actions…", text: $query)
                .focused($fieldFocused)
                .font(.paseo(.callout))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { activateSelection() }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .accessibilityLabel("Search")
                .accessibilityIdentifier("search.query")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.glyph(.regular))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.chip, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if flatRows.isEmpty {
                    Text(noResultsText)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 36)
                        .accessibilityIdentifier("search.noResults")
                } else {
                    ForEach(sections, id: \.header) { section in
                        sectionHeader(section.header)
                        ForEach(section.rows) { row in
                            rowView(row)
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.paseo(.caption, weight: .semibold))
            .foregroundStyle(Palette.tertiaryInk)
            .textCase(.uppercase)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isHeader)
    }

    private var flatRows: [Result] {
        sections.flatMap(\.rows)
    }

    private var sections: [(header: String, rows: [Result])] {
        var out: [(String, [Result])] = []
        let agents = agentRows
        if !agents.isEmpty {
            // Empty query shows the same rows under "Recents".
            out.append((trimmedQuery.isEmpty ? "Recents" : "Agents", agents))
        }
        let workspaces = workspaceRows
        if !workspaces.isEmpty { out.append(("Workspaces", workspaces)) }
        let projects = projectRows
        if !projects.isEmpty { out.append(("Projects", projects)) }
        let files = fileRows
        if !files.isEmpty {
            out.append((mentionIndex.isBuilding && mentionIndex.rows.isEmpty ? "Files (indexing…)" : "Files", files))
        }
        let actions = actionRows
        if !actions.isEmpty { out.append(("Actions", actions)) }
        return out
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noResultsText: String {
        let q = trimmedQuery
        return q.isEmpty ? "No recents yet" : "No results for “\(q)”"
    }

    // MARK: Group builders

    private var lifecycleEntries: [AgentSnapshot] {
        session.agentLifecycle.entries
    }

    private var agentRows: [Result] {
        let q = trimmedQuery
        if q.isEmpty {
            return Array(
                lifecycleEntries
                    .sorted { recency($0) > recency($1) }
                    .prefix(8)
            ).map { agentRow($0) }
        }
        let scored = lifecycleEntries.compactMap { agent -> (Int, AgentSnapshot)? in
            let title = title(for: agent)
            if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil {
                return (100, agent)
            }
            if title.range(of: q, options: .caseInsensitive) != nil {
                return (60, agent)
            }
            if let workspace = agentWorkspace(agent),
                workspaceMatchScore(workspace, q) != nil
            {
                return (30, agent)
            }
            return nil
        }
        return scored
            .sorted {
                if $0.0 != $1.0 { return $0.0 > $1.0 }
                return recency($0.1) > recency($1.1)
            }
            .prefix(8)
            .map { agentRow($0.1) }
    }

    private var workspaceRows: [Result] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return session.workspaceDirectory.workspaces
            .compactMap { workspace -> (Int, WorkspaceDescriptor)? in
                guard let score = workspaceMatchScore(workspace, q) else { return nil }
                return (score, workspace)
            }
            .sorted {
                if $0.0 != $1.0 { return $0.0 > $1.0 }
                return (activityDate($0.1) ?? .distantPast) > (activityDate($1.1) ?? .distantPast)
            }
            .prefix(5)
            .map { workspaceRow($0.1) }
    }

    private var projectRows: [Result] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return session.workspaceDirectory.projects
            .compactMap { project -> (Int, WorkspaceProjectDescriptor)? in
                let name = (project.projectCustomName ?? "") + " " + project.projectDisplayName
                if name.range(of: q, options: [.caseInsensitive, .anchored]) != nil {
                    return (100, project)
                }
                if name.range(of: q, options: .caseInsensitive) != nil {
                    return (60, project)
                }
                return nil
            }
            .sorted { $0.0 > $1.0 }
            .prefix(5)
            .map { projectRow($0.1) }
    }

    private var fileRows: [Result] {
        let q = trimmedQuery
        guard !q.isEmpty, openWorkspace != nil else { return [] }
        return mentionIndex.matches(query: q, recent: [])
            .filter { !$0.isDirectory }
            .prefix(5)
            .map { mentionRow in
                Result(
                    id: "file.\(mentionRow.path)", kind: .file,
                    title: (mentionRow.path as NSString).lastPathComponent,
                    subtitle: mentionRow.path, symbol: "doc",
                    dot: nil, archived: false, agent: nil, workspace: nil,
                    fileRow: mentionRow, action: nil, hostEntry: nil, keywords: "")
            }
    }

    private var actionRows: [Result] {
        let q = trimmedQuery
        let isTogglePanelVisible = onTogglePanel != nil
        let isSwitchHostVisible = hostSwitch != nil
        let all: [CommandAction] = CommandAction.allCases.filter { action in
            switch action {
            case .togglePanel: isTogglePanelVisible
            case .switchHost: isSwitchHostVisible
            case .importSession: onImportSession != nil
            default: true
            }
        }
        var rows: [Result] = []
        if q.isEmpty {
            rows = all.map(actionRow)
        } else {
            rows = all.compactMap { action in
                action.matchScore(q).map { _ in actionRow(action) }
            }
        }
        if q.isEmpty, hostExpanded, let hostSwitch, !hostSwitch.hosts.isEmpty {
            rows += hostSwitch.hosts.map { entry in
                Result(
                    id: "host.\(entry.id.uuidString)", kind: .hostEntry,
                    title: entry.label, subtitle: nil,
                    symbol: entry.isCurrent ? "checkmark.circle.fill" : "desktopcomputer",
                    dot: nil, archived: false, agent: nil, workspace: nil,
                    fileRow: nil, action: nil, hostEntry: entry, keywords: "")
            }
        }
        return rows
    }

    // MARK: Row builders

    private func agentRow(_ agent: AgentSnapshot) -> Result {
        let title = title(for: agent)
        var subtitle = workspaceDisplayName(for: agent) ?? ""
        if let provider = session.agentControl.provider(agent.provider)?.label {
            subtitle += subtitle.isEmpty ? provider : " · \(provider)"
        }
        return Result(
            id: "agent.\(agent.id)", kind: .agent, title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle, symbol: nil,
            dot: agentDot(agent), archived: agent.archivedAt != nil,
            agent: agent, workspace: nil, fileRow: nil, action: nil,
            hostEntry: nil, keywords: "")
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> Result {
        let title = workspaceTitle(workspace)
        var meta = workspace.projectDisplayName
        if let branch = workspace.branch, !branch.isEmpty {
            meta += " · \(branch)"
        }
        if workspace.workspaceKind == .worktree {
            meta += " · Worktree"
        }
        return Result(
            id: "ws.\(workspace.id)", kind: .workspace, title: title,
            subtitle: meta, symbol: nil, dot: workspaceDot(workspace),
            archived: false, agent: nil, workspace: workspace, fileRow: nil,
            action: nil, hostEntry: nil, keywords: "")
    }

    private func projectRow(_ project: WorkspaceProjectDescriptor) -> Result {
        let workspace = session.workspaceDirectory.workspaces
            .filter { $0.projectId == project.projectId }
            .max {
                (activityDate($0) ?? .distantPast) < (activityDate($1) ?? .distantPast)
            }
        return Result(
            id: "project.\(project.projectId)", kind: .project,
            title: project.projectCustomName ?? project.projectDisplayName,
            subtitle: project.projectRootPath, symbol: "folder",
            dot: nil, archived: false, agent: nil, workspace: workspace,
            fileRow: nil, action: nil, hostEntry: nil, keywords: "")
    }

    private func actionRow(_ action: CommandAction) -> Result {
        Result(
            id: "action.\(action.rawValue)", kind: .action,
            title: action.title, subtitle: nil, symbol: action.symbol,
            dot: nil, archived: false, agent: nil, workspace: nil,
            fileRow: nil, action: action, hostEntry: nil, keywords: "")
    }

    private func agentDot(_ agent: AgentSnapshot) -> PaseoStatusDot.Kind {
        if agent.archivedAt != nil { return .idle }
        if agent.attention == .permission { return .needsInput }
        if agent.attention == .error || agent.status == .error { return .failed }
        if agent.status == .running { return .running }
        if agent.attention == .finished { return .unread }
        return .idle
    }

    private func workspaceDot(_ workspace: WorkspaceDescriptor) -> PaseoStatusDot.Kind {
        let agents = session.agents.filter { $0.workspaceId == workspace.id }
        if agents.contains(where: { $0.attention == .permission }) { return .needsInput }
        if agents.contains(where: { $0.attention == .error || $0.status == .error }) { return .failed }
        if agents.contains(where: { $0.status == .running }) { return .running }
        if agents.contains(where: { $0.attention == .finished }) { return .unread }
        return .idle
    }

    private var openWorkspace: WorkspaceDescriptor? {
        guard
            let selected = selectedAgentId,
            let agent = session.agents.first(where: { $0.id == selected })
                ?? lifecycleEntries.first(where: { $0.id == selected }),
            let workspaceId = agent.workspaceId
        else { return nil }
        return session.workspaceDirectory.workspace(id: workspaceId)
    }

    private func agentWorkspace(_ agent: AgentSnapshot) -> WorkspaceDescriptor? {
        guard let workspaceId = agent.workspaceId else { return nil }
        return session.workspaceDirectory.workspace(id: workspaceId)
    }

    private func workspaceDisplayName(for agent: AgentSnapshot) -> String? {
        agentWorkspace(agent).map(workspaceTitle)
    }

    private func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        let title = workspace.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? workspace.name
    }

    private func title(for agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? "New agent"
    }

    private func workspaceMatchScore(_ workspace: WorkspaceDescriptor, _ q: String) -> Int? {
        let title = workspaceTitle(workspace)
        if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 100 }
        if title.range(of: q, options: .caseInsensitive) != nil { return 60 }
        let project = workspace.projectDisplayName
        if project.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 50 }
        if project.range(of: q, options: .caseInsensitive) != nil { return 30 }
        if let branch = workspace.branch,
            branch.range(of: q, options: .caseInsensitive) != nil
        {
            return 40
        }
        return nil
    }

    private func recency(_ agent: AgentSnapshot) -> Date {
        for stamp in [agent.updatedAt, agent.lastUserMessageAt] {
            if let stamp, let date = PaseoDate.parse(stamp) { return date }
        }
        return .distantPast
    }

    private func activityDate(_ workspace: WorkspaceDescriptor) -> Date? {
        var best: Date?
        for agent in session.agents where agent.workspaceId == workspace.id {
            best = max(best ?? .distantPast, recency(agent))
        }
        if let best { return best }
        for stamp in [workspace.activityAt, workspace.lastUserMessageAt, workspace.createdAt] {
            if let stamp, let date = PaseoDate.parse(stamp) { return date }
        }
        return nil
    }

    // MARK: Rows

    private func rowView(_ row: Result) -> some View {
        let index = flatRows.firstIndex { $0.id == row.id } ?? 0
        let isSelected = index == selectedIndex
        return Button {
            selectedIndex = index
            activate(row)
        } label: {
            HStack(spacing: 12) {
                leading(row)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(row.kind == .file ? .paseo(.codeCaption) : .paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                trailing(row)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(isSelected ? Palette.chip : .clear, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("search.row.\(row.id)")
    }

    @ViewBuilder private func leading(_ row: Result) -> some View {
        if let dot = row.dot {
            PaseoStatusDot(kind: dot)
        } else if let symbol = row.symbol {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .regular))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 22)
        } else {
            Color.clear.frame(width: 22)
        }
    }

    @ViewBuilder private func trailing(_ row: Result) -> some View {
        if row.archived {
            Text("Archived")
                .font(.paseo(.caption2, weight: .medium))
                .foregroundStyle(Palette.captionInk)
                .padding(.horizontal, 8)
                .frame(minHeight: 20)
                .background(Palette.chip, in: .rect(cornerRadius: Radius.xs))
        } else if row.kind == .action, row.action == .switchHost {
            Image(systemName: hostExpanded ? "chevron.up" : "chevron.down")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
        } else if row.kind == .hostEntry {
            EmptyView()
        } else {
            Color.clear
        }
    }

    // MARK: Activation

    private func activateSelection() {
        guard !flatRows.isEmpty else { return }
        activate(flatRows[min(selectedIndex, flatRows.count - 1)])
    }

    private func moveSelection(_ delta: Int) {
        let count = flatRows.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    private func activate(_ row: Result) {
        selectedIndex = flatRows.firstIndex { $0.id == row.id } ?? selectedIndex
        Haptics.selection()
        switch row.kind {
        case .agent:
            guard let agent = row.agent else { return }
            if agent.archivedAt != nil {
                Task {
                    _ = await session.agentLifecycle.unarchive(agentId: agent.id)
                    await session.refreshAgents()
                    onOpenAgent(agent.id)
                }
            } else {
                onOpenAgent(agent.id)
            }
        case .workspace:
            guard let workspace = row.workspace else { return }
            openWorkspace(workspace)
        case .project:
            if let workspace = row.workspace {
                openWorkspace(workspace)
            } else {
                onNewWorkspace()
            }
        case .file:
            guard let mentionRow = row.fileRow, let workspace = openWorkspace else { return }
            let checkout = session.checkout(for: workspace)
            fileViewer = FileViewerTarget(
                checkout: checkout, relPath: mentionRow.path)
        case .action:
            guard let action = row.action else { return }
            runAction(action)
        case .hostEntry:
            guard let entry = row.hostEntry, let hostSwitch else { return }
            onClose()
            hostSwitch.switchTo(entry.id)
        }
    }

    /// The selected workspace's newest agent; archived requires unarchive-then-open; none
    /// means create the first one.
    private func openWorkspace(_ workspace: WorkspaceDescriptor) {
        let liveNewest = session.agents
            .filter { $0.workspaceId == workspace.id }
            .max { recency($0) < recency($1) }
        if let agent = liveNewest {
            onOpenAgent(agent.id)
            return
        }
        let archivedNewest = lifecycleEntries
            .filter { $0.workspaceId == workspace.id }
            .max { recency($0) < recency($1) }
        if let archived = archivedNewest {
            Task {
                _ = await session.agentLifecycle.unarchive(agentId: archived.id)
                await session.refreshAgents()
                onOpenAgent(archived.id)
            }
            return
        }
        onNewAgent(workspace)
    }

    private func runAction(_ action: CommandAction) {
        switch action {
        case .newAgent:
            if let workspace = openWorkspace {
                onNewAgent(workspace)
            } else {
                onShowToast("Open a workspace to start an agent.")
            }
        case .newWorkspace:
            onNewWorkspace()
        case .importSession:
            onImportSession?()
        case .openSettings:
            onOpenSettings()
        case .togglePanel:
            onTogglePanel?()
            onClose()
        case .switchHost:
            hostExpanded.toggle()
        }
    }
}

private struct FileViewerTarget: Identifiable {
    let checkout: CheckoutStore
    let relPath: String
    var id: String { relPath }
}
#endif
