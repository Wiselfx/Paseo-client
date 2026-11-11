#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The drawer: ClaudeUI's sidebar layout on `WorkspaceDirectory`'s project → workspace groups.
/// Agents are not listed here; they are the tabs inside a workspace. Projects are the collapsible
/// level (collapsed state persisted per project); workspace rows aggregate their agents' status and
/// open the most recently active agent. The footer holds the Settings avatar and the New session
/// pill (UX-SPEC §2).
struct PaseoSidebar: View {
    let session: HostSession
    var selectedAgentId: String?
    var onSelectAgent: (String) -> Void
    /// Starts a session in the given workspace, or the most recently used one when nil (§2.2).
    var onNewSession: (String?) -> Void
    var onNewAgent: (WorkspaceDescriptor) -> Void
    /// The workspace of the conversation on screen; the New session pill targets it.
    var currentWorkspaceId: String?
    var onDisconnect: () -> Void
    /// Toggles the right-side workspace panel; nil hides the Toggle panel action in Search.
    var onTogglePanel: (() -> Void)? = nil
    /// Set by a deep link's `open-project` route (M20): present the Add project sheet once.
    @Binding var addProjectRequest: Bool

    @State var sheet: PaseoSidebarSheet?
    @State var showHidden = false
    @State var renamingWorkspace: WorkspaceDescriptor?
    @State var renamingProject: WorkspaceProjectDescriptor?
    @State var projectPendingRemoval: WorkspaceProjectDescriptor?
    @State var renameText = ""
    /// The comma-joined preferences, parsed once (§3).
    @State var preferences = SidebarPreferences()
    /// The workspace archive flow: the risk check and the two confirmations.
    @State var archive = WorkspaceArchiveActions()
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.sort") var sortRaw = SidebarSort.activity.rawValue
    @AppStorage("paseo.sidebar.showBranch") var showBranch = true
    @AppStorage("paseo.sidebar.showDiffStats") var showDiffStats = true
    @AppStorage("paseo.sidebar.showPRBadge") var showPRBadge = true
    @AppStorage("paseo.sidebar.groupBy") var groupByRaw = SidebarGrouping.project.rawValue
    /// Running workspaces float to the top of their group. Default on.
    @AppStorage("paseo.sidebar.activeFirst") var activeFirst = true
    /// The sidebar label filter: the raw label name, or "" for All (one at a time, by design).
    @AppStorage("paseo.sidebar.labelFilter") var labelFilter = ""
    /// Shared with the Settings → Sidebar toggle, which owns this row. Hidden by default.
    @AppStorage("paseo.usage.showInSidebar") var showUsageInSidebar = false
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showHistory") var showHistory = true
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showSchedules") var showSchedules = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.toast) var toast
    /// R5's drawer, for the ⌘K hook: the sidebar owns the Search sheet.
    @Environment(\.shellDrawer) private var shellDrawer
    /// False while the drawer shows the sidebar itself (H4 §2). The usage footer refreshes on
    /// that edge — a commit, not a drag frame.
    @Environment(\.isSurfaceObscured) private var isSurfaceObscured

    var body: some View {
        // Derived once per evaluation and shared by the directory and every row (P5 #3).
        let derivations = sidebarDerivations()
        let chrome = VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo")
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                Spacer()
                displayOptionsMenu
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    navigation
                    directory(derivations: derivations)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                // The action is `@Sendable`: capture the session, not this view.
                await session.workspaceDirectory.refresh()
                await session.refreshAgents()
            }

            usageSection
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // The sidebar canvas equals the conversation canvas (§1.1); only the card's hairline
        // and dim separate the two surfaces.
        .background(Palette.sidebar)
        .foregroundStyle(Palette.ink)
        .onAppear {
            // R5's ⌘K hook: the sidebar owns the Search sheet, so it hands the route over here.
            shellDrawer?.onSearch = {
                shellDrawer?.open(.sidebar)
                sheet = .search
            }
            consumeAddProjectRequest()
            loadDirectoryIfNeeded()
        }
        // Usage is state-driven, never appear-driven (H4 §2): the toggle, the host's capability
        // and the host itself decide when a load is worth asking for.
        .task(id: usageLoadKey) { await loadUsage(forceRefresh: false) }
        .onChange(of: isSurfaceObscured) { _, obscured in
            guard !obscured else { return }
            Task { await loadUsage(forceRefresh: true) }
        }
        .onChange(of: addProjectRequest) { _, _ in
            consumeAddProjectRequest()
        }
        let sheeted = chrome.sheet(item: $sheet) { sheetContent($0) }
        return withArchiveDialogs(withRenameAlerts(sheeted))
    }

    @ViewBuilder
    func sheetContent(_ selection: PaseoSidebarSheet) -> some View {
        switch selection {
        case .settings:
            SettingsRoot(session: session, onDisconnect: onDisconnect)
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
        case .search:
            CommandCenterSheet(
                session: session,
                onOpenAgent: { agentId in
                    sheet = nil
                    onSelectAgent(agentId)
                },
                onNewAgent: { workspace in
                    sheet = nil
                    onNewAgent(workspace)
                },
                onNewWorkspace: { sheet = .newWorkspace },
                onOpenSettings: { sheet = .settings },
                onTogglePanel: onTogglePanel,
                onImportSession: session.agentControl.isSupported ? { sheet = .importSession } : nil,
                onShowToast: { showToast($0) },
                onClose: { sheet = nil },
                selectedAgentId: selectedAgentId)
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
        case .importSession:
            ImportSessionSheet(session: session) { agentId in
                sheet = nil
                onSelectAgent(agentId)
            }
        case .usage:
            ClaudeUsageReportsSheet(session: session)
        case .newLabel(let target):
            NewLabelSheet(session: session, workspace: target) { sheet = nil }
        case .labelsManager:
            LabelsManageSheet(session: session) { sheet = nil }
        case .project(let target):
            ProjectSettingsView(session: session, project: target)
        }
    }

    func withRenameAlerts(_ content: some View) -> some View {
        content
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
    }

    func withArchiveDialogs(_ content: some View) -> some View {
        content
        .confirmationDialog(
            "Archive worktree?",
            isPresented: Binding(
                get: { archive.pendingWarning != nil },
                set: { if !$0 { archive.pendingWarning = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                archive.confirmWarning(session: session, toast: toast)
            }
            Button("Cancel", role: .cancel) { archive.pendingWarning = nil }
        } message: {
            Text(archive.pendingWarning?.message ?? "")
        }
        .confirmationDialog(
            "Archive workspace?",
            isPresented: Binding(
                get: { archive.pendingConfirmation != nil },
                set: { if !$0 { archive.pendingConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                archive.confirmPending(session: session, toast: toast)
            }
            Button("Cancel", role: .cancel) { archive.pendingConfirmation = nil }
        } message: {
            Text("Its agents and terminals stop. This host can't undo an archive.")
        }
        .confirmationDialog(
            ProjectActions.removeTitle,
            isPresented: Binding(
                get: { projectPendingRemoval != nil },
                set: { if !$0 { projectPendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                guard let project = projectPendingRemoval else { return }
                projectPendingRemoval = nil
                ProjectActions.remove(project, session: session, toast: toast)
            }
            Button("Cancel", role: .cancel) { projectPendingRemoval = nil }
        } message: {
            Text(ProjectActions.removeMessage)
        }
    }

    // MARK: Navigation

    private var navigation: some View {
        VStack(spacing: 0) {
            ListRow(title: "Search", systemImage: "magnifyingglass") { sheet = .search }
            if showHistory {
                ListRow(title: "History", systemImage: "clock.arrow.2.circlepath") {
                    sheet = .history
                }
            }
            if showSchedules {
                ListRow(title: "Schedules", systemImage: "clock") { sheet = .schedules }
            }
            if session.agentControl.isSupported {
                ListRow(title: "Import session", systemImage: "square.and.arrow.down") {
                    sheet = .importSession
                }
            }
            if session.workspaceDirectory.supportsProjectAdd {
                ListRow(title: "Add project", systemImage: "folder.badge.plus") {
                    sheet = .addProject
                }
            }
            if session.workspaceDirectory.supportsWorkspaceCreate {
                ListRow(title: "New workspace", systemImage: "plus") { sheet = .newWorkspace }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Usage

    /// One meter the footer can draw: a provider's summary window with its percentage and reset.
    private struct UsageFooterLine: Identifiable {
        let id: String
        let source: String
        let label: String
        let used: Double
        let resetsAt: String?
    }

    /// What the footer shows when there is no meter to draw. `retries` separates "ask the host
    /// again" from "open the sheet, which explains".
    private enum UsageStatus {
        case loading
        case message(String, retries: Bool)
    }

    /// The footer's usage block: one line per summary window, otherwise exactly one line of state.
    /// It is never empty while the toggle is on, so the page above it keeps its height and the
    /// rows do not move when the first load lands (H4 §2).
    @ViewBuilder private var usageSection: some View {
        if showUsageInSidebar {
            VStack(spacing: 4) {
                let lines = usageLines
                if lines.isEmpty {
                    usageStatusLine
                } else {
                    ForEach(lines) { line in
                        usageFooterLine(line)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            // The meters arriving is a size change of the page: animate it, never snap it
            // (H4 §2). Reduce Motion keeps the layout change, without the curve.
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion), value: usageLines.count)
            .animation(
                Motion.fade.resolved(reduceMotion: reduceMotion), value: showUsageInSidebar)
        }
    }

    /// The meters, built once per body: a report's pinned windows (or its first window), only when
    /// the host gave them a percentage.
    private var usageLines: [UsageFooterLine] {
        session.hostUsage.reports.flatMap { report -> [UsageFooterLine] in
            guard case .available(let available) = report.report else { return [] }
            return summaryWindows(available).compactMap { window in
                guard let used = window.usedPct else { return nil }
                return UsageFooterLine(
                    id: "\(report.sourceId).\(window.id)",
                    source: report.sourceLabel,
                    label: window.label,
                    used: used,
                    resetsAt: window.resetsAt)
            }
        }
    }

    private var usageStatus: UsageStatus {
        guard session.hostUsage.isSupported else {
            return .message(HostUsageStore.unsupportedMessage, retries: false)
        }
        switch session.hostUsage.phase {
        case .idle, .loading:
            return .loading
        case .ready:
            // Upstream `providerUsage.empty` (en.ts:2249): the host answered, and no account had a
            // quota window to draw.
            return .message("No usage data", retries: false)
        case .failed(let message):
            return .message(message, retries: true)
        }
    }

    /// One caption line — the same height as a usage line, so the footer never changes height by
    /// itself.
    @ViewBuilder private var usageStatusLine: some View {
        switch usageStatus {
        case .loading:
            usageCaption("Loading usage…")
        case .message(let text, let retries):
            Button {
                if retries {
                    Task { _ = await session.hostUsage.load(forceRefresh: true) }
                } else {
                    sheet = .usage
                }
            } label: {
                usageCaption(text)
            }
            .buttonStyle(.plain)
            .accessibilityHint(retries ? "Tries again" : "Opens usage")
            .accessibilityIdentifier("sidebar.usage.status")
        }
    }

    private func usageCaption(_ text: String) -> some View {
        Text(text)
            .font(.paseo(.caption))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
    }

    private func summaryWindows(_ available: AvailableUsageReport) -> [ProviderUsageWindow] {
        let flagged = available.windows.filter { $0.summary == true }
        if flagged.isEmpty { return Array(available.windows.prefix(1)) }
        return Array(flagged.prefix(2))
    }

    private func usageFooterLine(_ line: UsageFooterLine) -> some View {
        let resets = ClaudeUsageResets.short(afterISO: line.resetsAt)
        let percent = Int(min(max(line.used, 0), 100).rounded())
        return Button {
            sheet = .usage
        } label: {
            HStack(spacing: 8) {
                Text("\(line.source) · \(line.label)")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                ClaudeUsageBar(percent: line.used, width: 44)
                Text(resets.map { "\(percent)% · \($0)" } ?? "\(percent)%")
                    .monospacedDigit()
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(line.source), \(line.label), \(percent) percent used"
                + (resets.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("sidebar.usage.\(line.id)")
    }

    /// The three facts a usage load depends on: the toggle, the host's capability, and the host
    /// itself. `.task(id:)` re-runs on a change of one of them — never per frame.
    private var usageLoadKey: String {
        "\(showUsageInSidebar)|\(session.hostUsage.isSupported)|\(session.serverInfo?.serverId ?? "")"
    }

    /// The state-driven load: turning the toggle on, or a `server_info` that finally reports
    /// support, loads the footer without reopening the drawer. The throttle also covers a second
    /// trigger while one load is in flight.
    private func loadUsage(forceRefresh: Bool) async {
        guard showUsageInSidebar, session.hostUsage.needsAutomaticLoad() else { return }
        _ = await session.hostUsage.load(forceRefresh: forceRefresh)
    }

    // MARK: Footer

    /// Avatar leading, the inverted New session pill trailing, sized to its label and never
    /// truncated (§0.3, §2.5). The host lives in Settings only; the host chip is gone.
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                sheet = .settings
            } label: {
                Text(initial)
                    .font(.paseo(.title, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Spacer(minLength: 8)

            newSessionPill
        }
        .padding(.horizontal, Space.lg)
        .padding(.bottom, 6)
    }

    private var newSessionPill: some View {
        Button {
            // The shell settles the drawer and plays the one haptic (PLAN §RH).
            onNewSession(currentWorkspaceId)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.glyph(.regular, weight: .semibold))
                Text("New session")
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.paseoPrimary())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("New session")
    }

    /// Every sidebar message goes through the shell's toast, which sits above sheets (§RI 8).
    func showToast(_ text: String) {
        toast?.show(text)
    }

    /// Pull-to-refresh and the error banner's retry: the directory and the agents together.
    private func refreshDirectory() async {
        await session.workspaceDirectory.refresh()
        await session.refreshAgents()
    }

    /// Also the error banner's action, from `SidebarDirectory`.
    func retryDirectory() {
        Task { await refreshDirectory() }
    }

    /// The first load, from `onAppear` so a body evaluation never triggers it.
    private func loadDirectoryIfNeeded() {
        guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else {
            return
        }
        Task { await session.workspaceDirectory.refresh() }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "P" }
        return String(first).uppercased()
    }

    /// A deep-link `open-project` request is one-shot: clear it before presenting, so a later
    /// sheet change or a re-render cannot re-open Add project.
    private func consumeAddProjectRequest() {
        guard addProjectRequest else { return }
        addProjectRequest = false
        sheet = .addProject
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


}
enum PaseoSidebarSheet: Identifiable {
    case settings
    case schedules
    case history
    case search
    case newWorkspace
    case addProject
    case importSession
    case usage
    case newLabel(WorkspaceDescriptor)
    case labelsManager
    case project(WorkspaceProjectDescriptor)

    var id: String {
        switch self {
        case .settings: "settings"
        case .schedules: "schedules"
        case .history: "history"
        case .search: "search"
        case .newWorkspace: "newWorkspace"
        case .addProject: "addProject"
        case .importSession: "importSession"
        case .usage: "usage"
        case .newLabel(let target): "newLabel:\(target.id)"
        case .labelsManager: "labelsManager"
        case .project(let target): "project:\(target.projectId)"
        }
    }
}


#endif
