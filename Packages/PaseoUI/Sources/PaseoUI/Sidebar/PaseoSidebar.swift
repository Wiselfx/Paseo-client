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
    /// Shared with the Settings → General toggle, which owns this row. Hidden by default.
    @AppStorage("paseo.usage.showInSidebar") var showUsageInSidebar = false
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showHistory") var showHistory = true
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showSchedules") var showSchedules = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.toast) var toast
    /// R5's drawer, for the ⌘K hook: the sidebar owns the Search sheet.
    @Environment(\.shellDrawer) private var shellDrawer


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
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .onAppear {
            // R5's ⌘K hook: the sidebar owns the Search sheet, so it hands the route over here.
            shellDrawer?.onSearch = {
                shellDrawer?.open(.sidebar)
                sheet = .search
            }
            if showUsageInSidebar && session.hostUsage.isSupported {
                Task { _ = await session.hostUsage.load(forceRefresh: false) }
            }
            consumeAddProjectRequest()
            loadDirectoryIfNeeded()
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

    /// One compact line per available provider report, with its pinned (or first) window:
    /// "62% · resets 3h". Hidden entirely unless enabled in Settings → General.
    @ViewBuilder private var usageSection: some View {
        if showsUsageFooter {
            VStack(spacing: 4) {
                ForEach(session.hostUsage.reports) { report in
                    if case .available(let available) = report.report {
                        ForEach(summaryWindows(available)) { window in
                            if let used = window.usedPct {
                                usageFooterLine(source: report.sourceLabel, window: window, used: used)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    /// One switch (Settings → General owns it) plus the host's support; a host with usage off
    /// reports the failure itself, so its own policy is not a second gate.
    private var showsUsageFooter: Bool {
        showUsageInSidebar && session.hostUsage.isSupported
    }

    private func summaryWindows(_ available: AvailableUsageReport) -> [ProviderUsageWindow] {
        let flagged = available.windows.filter { $0.summary == true }
        if flagged.isEmpty { return Array(available.windows.prefix(1)) }
        return Array(flagged.prefix(2))
    }

    private func usageFooterLine(
        source: String, window: ProviderUsageWindow, used: Double
    ) -> some View {
        let resets = ClaudeUsageResets.short(afterISO: window.resetsAt)
        let percent = Int(min(max(used, 0), 100).rounded())
        return Button {
            Haptics.selection()
            sheet = .usage
        } label: {
            HStack(spacing: 8) {
                Text("\(source) · \(window.label)")
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                ClaudeUsageBar(percent: used, width: 44)
                Text(resets.map { "\(percent)% · \($0)" } ?? "\(percent)%")
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(source), \(window.label), \(percent) percent used"
                + (resets.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("sidebar.usage.\(source).\(window.id)")
    }

    // MARK: Footer

    /// Avatar leading, the inverted New session pill trailing, sized to its label and never
    /// truncated (§0.3, §2.5). The host lives in Settings only; the host chip is gone.
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.selection()
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
        .padding(.horizontal, 20)
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
