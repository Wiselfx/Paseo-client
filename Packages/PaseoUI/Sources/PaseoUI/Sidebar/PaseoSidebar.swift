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

    @State var sheet: PaseoSidebarSheet?
    @State var showHidden = false
    @State var renamingWorkspace: WorkspaceDescriptor?
    @State var renamingProject: WorkspaceProjectDescriptor?
    @State var projectPendingRemoval: WorkspaceProjectDescriptor?
    /// Set only when the daemon can't undo an archive: then a confirmation guards it instead.
    @State var workspacePendingArchive: WorkspaceDescriptor?
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
    @AppStorage("paseo.sidebar.groupByProject") var groupByProject = true
    @AppStorage("paseo.sidebar.hiddenWorkspaces") var hiddenWorkspaces = ""
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let typography = ClaudeTypography()

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


#endif
