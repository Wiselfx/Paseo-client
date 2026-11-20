#if canImport(UIKit)
import Foundation
import Observation
import PaseoStore
import SwiftUI
import UIKit

/// The command center's results, built once per input change (PLAN §RE, R-1): the query is
/// debounced at 100 ms, and workspace activity is folded into one dictionary per agents change so
/// neither a comparator nor a row's status dot ever scans the agent list.
@MainActor @Observable final class SearchModel {
    enum ResultKind: Equatable { case agent, workspace, project, file, action, hostEntry }

    /// One flattened row in the results list; carries everything needed to render and act.
    struct Result: Identifiable {
        let id: String
        let kind: ResultKind
        let title: String
        let subtitle: String?
        let symbol: String?
        let dot: StatusDot.State?
        let archived: Bool
        let agent: AgentSnapshot?
        let workspace: WorkspaceDescriptor?
        let fileRow: MentionIndexRow?
        let action: CommandAction?
        let hostEntry: HostSwitchEntry?
    }

    struct Section: Identifiable {
        var id: String { header }
        let header: String
        let rows: [Result]
    }

    /// A workspace's rolled-up agent state, computed once when the agents change.
    struct WorkspaceActivity {
        var latestActivity: Date = .distantPast
        var isRunning = false
        var needsInput = false
        var failed = false
        var unread = false
    }

    private(set) var sections: [Section] = []
    private(set) var flatRows: [Result] = []

    /// The debounced query the sections were built for.
    private var query = ""
    private var agents: [AgentSnapshot] = []
    private var workspaces: [WorkspaceDescriptor] = []
    private var projects: [WorkspaceProjectDescriptor] = []
    private var files: MentionIndex?
    private var isLoadingFiles = false
    private var actions: [CommandAction] = []
    private var hostEntries: [HostSwitchEntry] = []
    private var hostExpanded = false

    /// Derived lookups, rebuilt with the inputs, never per section build.
    private var activityByWorkspace: [String: WorkspaceActivity] = [:]
    private var recencyByAgent: [String: Date] = [:]
    private var workspaceByID: [String: WorkspaceDescriptor] = [:]
    private var providerLabels: [String: String] = [:]
    /// The workspace whose files are searched; nil when no agent is open.
    private var fileWorkspaceID: String?

    init() {}

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isLoadingFilesIndex: Bool { isLoadingFiles && (files?.rows.isEmpty ?? true) }

    var noResultsText: String {
        trimmedQuery.isEmpty ? "No recents yet" : "No results for “\(trimmedQuery)”"
    }

    /// New inputs: agents, workspaces, projects, the file index and the action list. Rebuilds the
    /// derived lookups (workspace activity once) and then the sections.
    func update(
        agents: [AgentSnapshot],
        workspaces: [WorkspaceDescriptor],
        projects: [WorkspaceProjectDescriptor],
        files: MentionIndex?,
        isLoadingFiles: Bool,
        actions: [CommandAction],
        hostEntries: [HostSwitchEntry],
        hostExpanded: Bool,
        providerLabels: [String: String],
        fileWorkspaceID: String?
    ) {
        self.agents = agents
        self.workspaces = workspaces
        self.projects = projects
        self.files = files
        self.isLoadingFiles = isLoadingFiles
        self.actions = actions
        self.hostEntries = hostEntries
        self.hostExpanded = hostExpanded
        self.providerLabels = providerLabels
        self.fileWorkspaceID = fileWorkspaceID
        rebuildLookups()
        rebuild()
    }

    /// Only the actions changed (a menu expand, a capability appeared).
    func updateActions(_ actions: [CommandAction], hostEntries: [HostSwitchEntry], hostExpanded: Bool) {
        self.actions = actions
        self.hostEntries = hostEntries
        self.hostExpanded = hostExpanded
        rebuild()
    }

    func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        rebuild()
    }

    // MARK: Lookups

    /// One pass over the agents: recency by id, and the per-workspace roll-up the dots read.
    private func rebuildLookups() {
        var activity: [String: WorkspaceActivity] = [:]
        var recency: [String: Date] = [:]
        var byID: [String: WorkspaceDescriptor] = [:]
        for workspace in workspaces {
            byID[workspace.id] = workspace
            activity[workspace.id] = WorkspaceActivity()
        }
        for agent in agents {
            let date = Self.recency(agent)
            recency[agent.id] = date
            guard let workspaceId = agent.workspaceId, var entry = activity[workspaceId] else {
                continue
            }
            if date > entry.latestActivity { entry.latestActivity = date }
            if agent.status == .running { entry.isRunning = true }
            if agent.attention == .permission { entry.needsInput = true }
            if agent.attention == .error || agent.status == .error { entry.failed = true }
            if agent.attention == .finished { entry.unread = true }
            activity[workspaceId] = entry
        }
        activityByWorkspace = activity
        recencyByAgent = recency
        workspaceByID = byID
    }

    // MARK: Build

    private func rebuild() {
        var out: [Section] = []
        let agentRows = buildAgentRows()
        if !agentRows.isEmpty {
            // An empty query shows the same rows under "Recents".
            out.append(Section(header: trimmedQuery.isEmpty ? "Recents" : "Agents", rows: agentRows))
        }
        let workspaceRows = buildWorkspaceRows()
        if !workspaceRows.isEmpty { out.append(Section(header: "Workspaces", rows: workspaceRows)) }
        let projectRows = buildProjectRows()
        if !projectRows.isEmpty { out.append(Section(header: "Projects", rows: projectRows)) }
        let fileRows = buildFileRows()
        if !fileRows.isEmpty {
            out.append(
                Section(
                    header: isLoadingFilesIndex ? "Files (indexing…)" : "Files", rows: fileRows))
        }
        let actionRows = buildActionRows()
        if !actionRows.isEmpty { out.append(Section(header: "Actions", rows: actionRows)) }
        sections = out
        flatRows = out.flatMap(\.rows)
    }

    private func buildAgentRows() -> [Result] {
        let q = trimmedQuery
        if q.isEmpty {
            return agents
                .sorted { recency($0) > recency($1) }
                .prefix(8)
                .map(agentRow)
        }
        let scored: [(score: Int, agent: AgentSnapshot)] = agents.compactMap { agent in
            let title = Self.title(for: agent)
            if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil {
                return (100, agent)
            }
            if title.localizedStandardContains(q) {
                return (60, agent)
            }
            if let workspace = self.workspace(for: agent),
                workspaceMatchScore(workspace, q) != nil
            {
                return (30, agent)
            }
            return nil
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return recency($0.agent) > recency($1.agent)
            }
            .prefix(8)
            .map { agentRow($0.agent) }
    }

    private func buildWorkspaceRows() -> [Result] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        let scored: [(score: Int, workspace: WorkspaceDescriptor)] = workspaces.compactMap {
            workspace in
            guard let score = workspaceMatchScore(workspace, q) else { return nil }
            return (score, workspace)
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return activity($0.workspace).latestActivity
                    > activity($1.workspace).latestActivity
            }
            .prefix(5)
            .map { workspaceRow($0.workspace) }
    }

    private func buildProjectRows() -> [Result] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        let scored: [(score: Int, project: WorkspaceProjectDescriptor)] = projects.compactMap {
            project in
            let name = (project.projectCustomName ?? "") + " " + project.projectDisplayName
            if name.range(of: q, options: [.caseInsensitive, .anchored]) != nil {
                return (100, project)
            }
            if name.localizedStandardContains(q) {
                return (60, project)
            }
            return nil
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { projectRow($0.project) }
    }

    private func buildFileRows() -> [Result] {
        let q = trimmedQuery
        guard !q.isEmpty, fileWorkspaceID != nil, let files else { return [] }
        return files.matches(query: q, recent: [])
            .filter { !$0.isDirectory }
            .prefix(5)
            .map { mentionRow in
                Result(
                    id: "file.\(mentionRow.path)", kind: .file,
                    title: (mentionRow.path as NSString).lastPathComponent,
                    subtitle: mentionRow.path, symbol: "doc",
                    dot: nil, archived: false, agent: nil, workspace: nil,
                    fileRow: mentionRow, action: nil, hostEntry: nil)
            }
    }

    private func buildActionRows() -> [Result] {
        let q = trimmedQuery
        var rows: [Result]
        if q.isEmpty {
            rows = actions.map(actionRow)
        } else {
            rows = actions.compactMap { action in
                action.matchScore(q).map { _ in actionRow(action) }
            }
        }
        if q.isEmpty, hostExpanded, !hostEntries.isEmpty {
            rows += hostEntries.map { entry in
                Result(
                    id: "host.\(entry.id.uuidString)", kind: .hostEntry,
                    title: entry.label, subtitle: nil,
                    symbol: entry.isCurrent ? "checkmark.circle.fill" : "desktopcomputer",
                    dot: nil, archived: false, agent: nil, workspace: nil,
                    fileRow: nil, action: nil, hostEntry: entry)
            }
        }
        return rows
    }

    // MARK: Rows

    private func agentRow(_ agent: AgentSnapshot) -> Result {
        let title = Self.title(for: agent)
        var subtitle = workspace(for: agent).map(workspaceTitle) ?? ""
        if let provider = providerLabels[agent.provider] {
            subtitle += subtitle.isEmpty ? provider : " · \(provider)"
        }
        return Result(
            id: "agent.\(agent.id)", kind: .agent, title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle, symbol: nil,
            dot: agentDot(agent), archived: agent.archivedAt != nil,
            agent: agent, workspace: nil, fileRow: nil, action: nil, hostEntry: nil)
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> Result {
        var meta = workspace.projectDisplayName
        if let branch = workspace.branch, !branch.isEmpty {
            meta += " · \(branch)"
        }
        if workspace.workspaceKind == .worktree {
            meta += " · Worktree"
        }
        return Result(
            id: "ws.\(workspace.id)", kind: .workspace, title: workspaceTitle(workspace),
            subtitle: meta, symbol: nil, dot: workspaceDot(workspace),
            archived: false, agent: nil, workspace: workspace, fileRow: nil,
            action: nil, hostEntry: nil)
    }

    private func projectRow(_ project: WorkspaceProjectDescriptor) -> Result {
        let newest = workspaces
            .filter { $0.projectId == project.projectId }
            .max { activity($0).latestActivity < activity($1).latestActivity }
        return Result(
            id: "project.\(project.projectId)", kind: .project,
            title: project.projectCustomName ?? project.projectDisplayName,
            subtitle: project.projectRootPath, symbol: "folder",
            dot: nil, archived: false, agent: nil, workspace: newest,
            fileRow: nil, action: nil, hostEntry: nil)
    }

    private func actionRow(_ action: CommandAction) -> Result {
        Result(
            id: "action.\(action.rawValue)", kind: .action,
            title: action.title, subtitle: nil, symbol: action.symbol,
            dot: nil, archived: false, agent: nil, workspace: nil,
            fileRow: nil, action: action, hostEntry: nil)
    }

    // MARK: Dots

    private func agentDot(_ agent: AgentSnapshot) -> StatusDot.State {
        if agent.archivedAt != nil { return .idle }
        if agent.attention == .permission { return .attention }
        if agent.attention == .error || agent.status == .error { return .failed }
        if agent.status == .running { return .running }
        if agent.attention == .finished { return .unread }
        return .idle
    }

    /// Reads the precomputed roll-up; never scans the agent list.
    private func workspaceDot(_ workspace: WorkspaceDescriptor) -> StatusDot.State {
        let entry = activity(workspace)
        if entry.needsInput { return .attention }
        if entry.failed { return .failed }
        if entry.isRunning { return .running }
        if entry.unread { return .unread }
        return .idle
    }

    // MARK: Values

    private func activity(_ workspace: WorkspaceDescriptor) -> WorkspaceActivity {
        activityByWorkspace[workspace.id] ?? WorkspaceActivity()
    }

    private func recency(_ agent: AgentSnapshot) -> Date {
        recencyByAgent[agent.id] ?? Self.recency(agent)
    }

    private func workspace(for agent: AgentSnapshot) -> WorkspaceDescriptor? {
        guard let workspaceId = agent.workspaceId else { return nil }
        return workspaceByID[workspaceId]
    }

    private func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        let title = workspace.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? workspace.name
    }

    private func workspaceMatchScore(_ workspace: WorkspaceDescriptor, _ q: String) -> Int? {
        let title = workspaceTitle(workspace)
        if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 100 }
        if title.localizedStandardContains(q) { return 60 }
        let project = workspace.projectDisplayName
        if project.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 50 }
        if project.localizedStandardContains(q) { return 30 }
        if let branch = workspace.branch, branch.localizedStandardContains(q) {
            return 40
        }
        return nil
    }

    /// `updatedAt`, else `lastUserMessageAt`: parsed once per input change.
    static func recency(_ agent: AgentSnapshot) -> Date {
        for stamp in [agent.updatedAt, agent.lastUserMessageAt] {
            if let stamp, let date = PaseoDate.parse(stamp) { return date }
        }
        return .distantPast
    }

    static func title(for agent: AgentSnapshot) -> String {
        let title = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false ? title : nil) ?? "New agent"
    }
}
extension SearchModel {
    /// One command the search sheet can run.
    enum CommandAction: String, CaseIterable {
        case newSession
        case newWorkspace
        case importSession
        case openHistory
        case openSchedules
        case openUsage
        case openSettings
        case togglePanel
        case switchHost

        var title: String {
            switch self {
            case .newSession: "New session"
            case .newWorkspace: "New workspace"
            case .importSession: "Import session"
            case .openHistory: "History"
            case .openSchedules: "Schedules"
            case .openUsage: "Usage"
            case .openSettings: "Open settings"
            case .togglePanel: "Toggle panel"
            case .switchHost: "Switch host…"
            }
        }

        var symbol: String {
            switch self {
            case .newSession: "square.and.pencil"
            case .newWorkspace: "plus"
            case .importSession: "square.and.arrow.down"
            case .openHistory: "clock.arrow.2.circlepath"
            case .openSchedules: "clock"
            case .openUsage: "chart.bar"
            case .openSettings: "gearshape"
            case .togglePanel: "sidebar.right"
            case .switchHost: "desktopcomputer"
            }
        }

        var keywords: String {
            switch self {
            case .newSession: "create start run"
            case .newWorkspace: "create add worktree"
            case .importSession: "existing cli terminal session resume host"
            case .openHistory: "recent sessions archived agents"
            case .openSchedules: "recurring heartbeat automation"
            case .openUsage: "reports tokens plan limits"
            case .openSettings: "preferences gear"
            case .togglePanel: "sidebar right files changes terminal"
            case .switchHost: "daemon saved server machine"
            }
        }

        /// Scoring against the typed query; nil hides the row.
        func matchScore(_ q: String) -> Int? {
            if title.range(of: q, options: [.caseInsensitive, .anchored]) != nil { return 100 }
            if title.localizedStandardContains(q) { return 60 }
            if keywords.localizedStandardContains(q) { return 30 }
            return nil
        }
    }
}
#endif
