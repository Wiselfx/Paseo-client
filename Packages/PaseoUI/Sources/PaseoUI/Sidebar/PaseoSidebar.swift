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

    /// Created once; the properties below forward to it so the sidebar's extensions read them
    /// as before (see `SidebarState`).
    @State private var state = SidebarState()
    var sheet: PaseoSidebarSheet? {
        get { state.sheet }
        nonmutating set { state.sheet = newValue }
    }
    var showHidden: Bool {
        get { state.showHidden }
        nonmutating set { state.showHidden = newValue }
    }
    var renamingWorkspace: WorkspaceDescriptor? {
        get { state.renamingWorkspace }
        nonmutating set { state.renamingWorkspace = newValue }
    }
    var renamingProject: WorkspaceProjectDescriptor? {
        get { state.renamingProject }
        nonmutating set { state.renamingProject = newValue }
    }
    var projectPendingRemoval: WorkspaceProjectDescriptor? {
        get { state.projectPendingRemoval }
        nonmutating set { state.projectPendingRemoval = newValue }
    }
    var renameText: String {
        get { state.renameText }
        nonmutating set { state.renameText = newValue }
    }
    /// The comma-joined preferences, parsed once (§3).
    var preferences: SidebarPreferences { state.preferences }
    /// The workspace archive flow: the risk check and the two confirmations.
    var archive: WorkspaceArchiveActions { state.archive }
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.sort") var sidebarSort: SidebarSort = .activity
    @AppStorage("paseo.sidebar.showBranch") var showBranch = true
    @AppStorage("paseo.sidebar.showDiffStats") var showDiffStats = true
    @AppStorage("paseo.sidebar.showPRBadge") var showPRBadge = true
    /// Unknown stored values fall back to project.
    @AppStorage("paseo.sidebar.groupBy") var sidebarGrouping: SidebarGrouping = .project
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
    /// Upstream refreshes its reports on an interval only while the summary is on screen and the
    /// app is visible (`packages/app/src/usage/queries.ts:182-197`), so the app's own phase is one
    /// of the two facts that start and stop the poll.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = PaseoPerf.body("Sidebar")
        let _ = PaseoPerf.why(Self.self)
        let chrome = VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo")
                    .font(.paseo(.largeTitle))
                    .foregroundStyle(Palette.ink)
                Spacer()
                displayOptionsMenu
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SidebarNavigation(
                        session: session, showHistory: showHistory, showSchedules: showSchedules
                    ) { sheet = $0 }
                    // Reads the agent and workspace lists in its own body (R-1).
                    SidebarDirectoryHost(sidebar: self)
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
            SidebarFooter(initial: initial) {
                sheet = .settings
            } onNewSession: {
                onNewSession(currentWorkspaceId)
            }
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
        // Usage is state-driven, never appear-driven (H4 §2): the toggle, the host's capability,
        // the host itself and the app coming back to the front decide when a load is worth asking
        // for. The store's minute throttle keeps a foreground flip from re-asking at once.
        .task(id: usageLoadKey) { await loadUsage() }
        // The drawer flag and the five-minute poll live in a child that reads them, so a drawer motion
        // never re-evaluates this body (W1, rule 7).
        .background { SidebarUsageDriver(session: session, showUsage: showUsageInSidebar) { await loadUsage() } }
        .onChange(of: addProjectRequest) { _, _ in
            consumeAddProjectRequest()
        }
        return chrome
            .sheet(item: $state.sheet) { sheetContent($0) }
            .modifier(SidebarRenameAlerts(state: state, session: session))
            .workspaceArchiveDialogs(archive, session: session)
            .modifier(SidebarProjectRemovalDialog(state: state, session: session))
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

    // MARK: Usage

    /// The footer's usage block. Its own view, which reads the usage store — the narrow
    /// `@Observable` child — and nothing else, so a load never re-evaluates this page (H4 §2,
    /// R-1). This page only decides when a load is worth asking for.
    private var usageSection: some View {
        SidebarUsageFooter(
            hostUsage: session.hostUsage,
            showInSidebar: showUsageInSidebar,
            onOpenUsage: { sheet = .usage })
    }

    /// The facts a usage load depends on: the toggle, the host's capability, the host itself and
    /// the app being in front. `.task(id:)` re-runs on a change of one of them — never per frame.
    private var usageLoadKey: String {
        "\(showUsageInSidebar)|\(session.hostUsage.isSupported)|\(session.serverInfo?.serverId ?? "")|\(scenePhase)"
    }

    /// The state-driven load: turning the toggle on, or a `server_info` that finally reports
    /// support, loads the footer without reopening the drawer. The throttle also covers a second
    /// trigger while one load is in flight.
    ///
    /// Never `forceRefresh`: an automatic question asks the daemon, and the daemon decides whether
    /// its provider cache is stale. Only the user's own Retry and the sheet's pull-to-refresh force
    /// the providers' quota APIs (H4 §2).
    private func loadUsage() async {
        guard showUsageInSidebar, session.hostUsage.needsAutomaticLoad() else { return }
        _ = await session.hostUsage.load(forceRefresh: false)
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
#endif
