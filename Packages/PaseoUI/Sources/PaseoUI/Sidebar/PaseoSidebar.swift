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
    /// Set only when the daemon can't undo an archive: then a confirmation guards it instead.
    @State var workspacePendingArchive: WorkspaceDescriptor?
    /// Set when a worktree-kind workspace has uncommitted or unpushed changes.
    @State var workspacePendingArchiveWarning: WorktreeArchiveWarning?
    @State var undoToast: (id: String, name: String)?
    @State var undoToastToken = UUID()
    @State var renameText = ""
    @State var toast: String?
    @AppStorage(PaseoSettingsKeys.yourName) private var name = ""
    @AppStorage("paseo.sidebar.collapsedProjects") var collapsedProjects = ""
    @AppStorage("paseo.sidebar.sort") var sortRaw = SidebarSort.activity.rawValue
    @AppStorage("paseo.sidebar.showBranch") var showBranch = true
    @AppStorage("paseo.sidebar.showDiffStats") var showDiffStats = true
    @AppStorage("paseo.sidebar.showPRBadge") var showPRBadge = true
    @AppStorage("paseo.sidebar.groupBy") var groupByRaw = SidebarGrouping.project.rawValue
    /// Running workspaces float to the top of their group. Default on.
    @AppStorage("paseo.sidebar.activeFirst") var activeFirst = true
    /// Project ids whose "Set up worktree scripts" callout was dismissed.
    @AppStorage("paseo.sidebar.setupCalloutDismissed") var setupCalloutDismissed = ""
    /// Workspace ids manually marked unread (DSH manual-unread). Cleared on open.
    @AppStorage("paseo.sidebar.manualUnread") var manualUnread = ""
    /// Date-group ids (today/yesterday/day-2…day-6/earlier) whose section is collapsed.
    @AppStorage("paseo.sidebar.collapsedDateGroups") var collapsedDateGroups = ""
    @AppStorage("paseo.sidebar.hiddenWorkspaces") var hiddenWorkspaces = ""
    /// The sidebar label filter: the raw label name, or "" for All (one at a time, by design).
    @AppStorage("paseo.sidebar.labelFilter") var labelFilter = ""
    /// Shared with the Settings → General toggle, which owns this row. Hidden by default.
    @AppStorage("paseo.usage.showInSidebar") var showUsageInSidebar = false
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showHistory") var showHistory = true
    /// Shared with Settings → Sidebar; default shown.
    @AppStorage("paseo.sidebar.showSchedules") var showSchedules = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let typography = ClaudeTypography()

    var body: some View {
        let chrome = VStack(alignment: .leading, spacing: 0) {
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

            usageSection
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // The sidebar canvas equals the conversation canvas (§1.1); only the card's hairline
        // and dim separate the two surfaces.
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .onAppear {
            if showUsageInSidebar && session.hostUsage.isSupported {
                Task { _ = await session.hostUsage.load(forceRefresh: false) }
            }
            consumeAddProjectRequest()
        }
        .onChange(of: addProjectRequest) { _, _ in
            consumeAddProjectRequest()
        }
        let sheeted = chrome.sheet(item: $sheet) { sheetContent($0) }
        return withOverlays(withArchiveDialogs(withRenameAlerts(sheeted)))
            .onAppear {
                guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else { return }
                Task { await session.workspaceDirectory.refresh() }
            }
    }

    @ViewBuilder
    func sheetContent(_ selection: PaseoSidebarSheet) -> some View {
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
                get: { workspacePendingArchiveWarning != nil },
                set: { if !$0 { workspacePendingArchiveWarning = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let warning = workspacePendingArchiveWarning else { return }
                workspacePendingArchiveWarning = nil
                archiveWorkspace(warning.workspace)
            }
            Button("Cancel", role: .cancel) { workspacePendingArchiveWarning = nil }
        } message: {
            Text(workspacePendingArchiveWarning?.message ?? "")
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
    }

    func withOverlays(_ content: some View) -> some View {
        content
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
    }

    // MARK: Navigation

    private var navigation: some View {
        VStack(spacing: 0) {
            navigationRow("Search", symbol: "magnifyingglass") { sheet = .search }
            if showHistory {
                navigationRow("History", symbol: "clock.arrow.2.circlepath") { sheet = .history }
            }
            if showSchedules {
                navigationRow("Schedules", symbol: "clock") { sheet = .schedules }
            }
            if session.agentControl.isSupported {
                navigationRow("Import session", symbol: "square.and.arrow.down") {
                    sheet = .importSession
                }
            }
            if session.workspaceDirectory.supportsProjectAdd {
                navigationRow("Add project", symbol: "plus") { sheet = .addProject }
            }
            if session.workspaceDirectory.supportsWorkspaceCreate {
                navigationRow("New workspace", symbol: "plus") { sheet = .newWorkspace }
            }
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

    private var showsUsageFooter: Bool {
        showUsageInSidebar
            && session.hostUsage.isSupported
            && session.hostUsage.usageEnabled
            && !session.hostUsage.reports.isEmpty
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
                    .font(typography.sans(12))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .lineLimit(1)
                ClaudeUsageBar(percent: used, width: 44)
                Text(resets.map { "\(percent)% · \($0)" } ?? "\(percent)%")
                    .font(typography.sans(11))
                    .foregroundStyle(ClaudePalette.secondaryInk)
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
                    .font(typography.serif(18, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
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
            Haptics.selection()
            onNewSession(currentWorkspaceId)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("New session")
                    .font(typography.sans(16, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(ClaudePalette.background)
            .padding(.horizontal, 17)
            .frame(height: 44)
            .background(ClaudePalette.ink, in: .capsule)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("New session")
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
