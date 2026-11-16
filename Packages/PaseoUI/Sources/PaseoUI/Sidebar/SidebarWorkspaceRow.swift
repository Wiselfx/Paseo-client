#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One script in trouble on a row's meta line.
enum SidebarScriptDot: Equatable {
    case running
    case failed
}

/// Everything a workspace row draws, as plain values (R-2): the row skips its body when this is
/// equal. Built per realized row from the directory pass's shared `SidebarDerivations`.
struct SidebarRowModel: Equatable {
    let workspace: WorkspaceDescriptor
    let title: String
    let statusKind: StatusDot.State
    let selected: Bool
    let attention: Bool
    let manuallyUnread: Bool
    let hidden: Bool
    /// The most recently active agent of the workspace; a tap opens it.
    let firstAgentId: String?
    let branchText: String
    /// The compact age ("5m"), nil without an activity stamp.
    let ageText: String?
    let showBranch: Bool
    let showDiffStats: Bool
    let showPRBadge: Bool
    let labelDefinitions: [WorkspaceLabelDefinition]
    let scriptDots: [SidebarScriptDot]
    let scriptDotsLabel: String
    let supportsPinning: Bool
    let supportsLabels: Bool
    let labelCatalog: [WorkspaceLabelDefinition]
}

/// What a row can do. One object per directory pass, shared by every row; rows compare equal
/// without it (the closures it reaches are the sidebar's stable `@State` and the shell's actions).
@MainActor
final class SidebarRowActions {
    private let sidebar: PaseoSidebar

    init(sidebar: PaseoSidebar) {
        self.sidebar = sidebar
    }

    /// Tapping a workspace opens its most recently active agent; the other agents are the header's
    /// tab chips. Opening also clears a manual unread mark.
    func open(_ workspace: WorkspaceDescriptor, firstAgentId: String?) {
        // The tap moves the drawer, so the shell owns the haptic (PLAN §RH).
        sidebar.clearManualUnread(workspace)
        guard let firstAgentId else {
            // No agent yet: a draft in this workspace, like Search (audit C #6).
            sidebar.onNewSession(workspace.id)
            return
        }
        sidebar.onSelectAgent(firstAgentId)
    }

    func newSession(_ workspace: WorkspaceDescriptor) { sidebar.onNewSession(workspace.id) }

    func rename(_ workspace: WorkspaceDescriptor) {
        sidebar.renameText = workspace.title ?? workspace.name
        sidebar.renamingWorkspace = workspace
    }

    func togglePinned(_ workspace: WorkspaceDescriptor) {
        let session = sidebar.session
        Task {
            let ok = await session.workspaceDirectory.setPinned(workspace.id, !workspace.isPinned)
            if !ok {
                sidebar.showToast(session.workspaceDirectory.actionError ?? "Couldn't change the pin.")
            }
        }
    }

    func toggleUnread(_ workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleManualUnread(workspace)
    }

    func toggleLabel(_ label: WorkspaceLabelDefinition, on workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleLabel(label, on: workspace)
    }

    func newLabel(on workspace: WorkspaceDescriptor) { sidebar.sheet = .newLabel(workspace) }

    func copyPath(_ workspace: WorkspaceDescriptor) {
        Clipboard.copy(workspace.cwd)
        sidebar.showToast("Path copied")
    }

    func copyBranch(_ branch: String) {
        Clipboard.copy(branch)
        sidebar.showToast("Branch name copied")
    }

    func toggleHidden(_ workspace: WorkspaceDescriptor) {
        Haptics.selection()
        sidebar.toggleHiddenFromSidebar(workspace)
    }

    func archive(_ workspace: WorkspaceDescriptor) {
        sidebar.archive.request(workspace, session: sidebar.session, toast: sidebar.toast)
    }
}

/// A workspace row of the directory. `Equatable` on the model only (R-2), applied with `.equatable()`.
struct SidebarWorkspaceRow: View, Equatable {
    let model: SidebarRowModel
    let actions: SidebarRowActions

    nonisolated static func == (left: Self, right: Self) -> Bool { left.model == right.model }

    var body: some View {
        let workspace = model.workspace
        Button {
            actions.open(workspace, firstAgentId: model.firstAgentId)
        } label: {
            HStack(spacing: 8) {
                StatusDot(model.statusKind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.paseo(.callout, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    metaRow
                }
                Spacer(minLength: 0)
                if model.attention {
                    StatusDot(.unread)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background(model.selected ? Palette.chip : Color.clear, in: .rect(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            model.manuallyUnread
                ? "Manually marked unread" : (model.attention ? "Needs attention" : ""))
        .accessibilityAddTraits(model.selected ? .isSelected : [])
        .contextMenu {
            // PLAN §RH order: open-variants, edit verbs, copy, hide, then the destructive verb.
            Button("New session", systemImage: "plus") { actions.newSession(workspace) }
            Button("Rename…", systemImage: "pencil") { actions.rename(workspace) }
            if model.supportsPinning {
                Button(
                    workspace.isPinned ? "Unpin" : "Pin to top",
                    systemImage: workspace.isPinned ? "pin.slash" : "pin"
                ) {
                    actions.togglePinned(workspace)
                }
            }
            Button(
                model.manuallyUnread ? "Clear unread mark" : "Mark as unread",
                systemImage: model.manuallyUnread ? "checkmark.circle" : "circle"
            ) {
                actions.toggleUnread(workspace)
            }
            if model.supportsLabels {
                Menu("Labels", systemImage: "tag") {
                    labelsSubmenu
                }
            }
            Button("Copy path", systemImage: "doc.on.doc") { actions.copyPath(workspace) }
            if let branch = workspace.branch {
                Button("Copy branch name", systemImage: "doc.on.doc") { actions.copyBranch(branch) }
            }
            Button(
                model.hidden ? "Unhide" : "Hide",
                systemImage: model.hidden ? "eye" : "eye.slash"
            ) {
                actions.toggleHidden(workspace)
            }
            Divider()
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                actions.archive(workspace)
            }
        }
    }

    /// The labels submenu: checkmark for assignments, "New label…" to mint one (and assign it) in place.
    @ViewBuilder private var labelsSubmenu: some View {
        let workspace = model.workspace
        if model.labelCatalog.isEmpty {
            Text("No labels yet")
        }
        ForEach(model.labelCatalog, id: \.name) { label in
            Button {
                actions.toggleLabel(label, on: workspace)
            } label: {
                HStack(spacing: 8) {
                    WorkspaceLabelDot(color: label.color)
                    Text(label.name)
                    Spacer(minLength: 12)
                    if (workspace.labels ?? []).contains(where: {
                        $0.caseInsensitiveCompare(label.name) == .orderedSame
                    }) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Divider()
        Button("New label…", systemImage: "plus") { actions.newLabel(on: workspace) }
    }

    private var hasVisibleDiffStat: Bool {
        guard model.showDiffStats, let stat = model.workspace.diffStat else { return false }
        return stat.additions > 0 || stat.deletions > 0
    }

    private var metaRow: some View {
        let workspace = model.workspace
        return HStack(spacing: 4) {
            if model.showBranch {
                Text(model.branchText)
                    .font(.paseo(.codeSmall))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if model.showDiffStats, let stat = workspace.diffStat, stat.additions > 0 || stat.deletions > 0 {
                if model.showBranch { Text("·").foregroundStyle(Palette.captionInk) }
                // The title gives way, the numbers never do (D3 §1).
                DiffStat(added: stat.additions, removed: stat.deletions, compact: true)
                    .fixedSize()
                    .layoutPriority(1)
                    .opacity(0.75)
            }
            if let age = model.ageText {
                if model.showBranch || hasVisibleDiffStat {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                Text(age)
                    .fixedSize()
                    .layoutPriority(1)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if !model.labelDefinitions.isEmpty {
                if model.showBranch || hasVisibleDiffStat || model.ageText != nil {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                WorkspaceLabelChips(definitions: model.labelDefinitions)
            }
            Spacer(minLength: 6)
            if model.showPRBadge, let pullRequest = workspace.githubRuntime?.pullRequest,
                let number = pullRequest.number
            {
                Text(verbatim: "#\(number)")
                    .font(.paseo(.caption2, weight: .semibold))
                    .foregroundStyle(Self.pullRequestTint(pullRequest))
            }
            if !model.scriptDots.isEmpty {
                HStack(spacing: 3) {
                    ForEach(0..<model.scriptDots.count, id: \.self) { index in
                        Circle()
                            .fill(model.scriptDots[index] == .running ? Palette.successInk : Palette.failureInk)
                            .frame(width: 5, height: 5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.scriptDotsLabel)
            }
        }
        .font(.paseo(.caption))
        .lineLimit(1)
    }

    private static func pullRequestTint(_ pr: WorkspaceGitHubRuntime.WorkspacePullRequest) -> Color {
        if pr.isMerged { return Palette.unread }
        if pr.isDraft == true { return Palette.tertiaryInk }
        switch pr.state.lowercased() {
        case "open": return Palette.successInk
        case "closed": return Palette.failureInk
        default: return Palette.secondaryInk
        }
    }
}

extension PaseoSidebar {
    func workspaceRow(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> some View {
        SidebarWorkspaceRow(
            model: rowModel(workspace, derivations: derivations), actions: derivations.actions
        )
        .equatable()
    }

    /// The row's values, read once per realized row in the directory pass.
    func rowModel(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> SidebarRowModel {
        let rowAgents = agents(in: workspace, derivations: derivations)
        let manuallyUnread = isManuallyUnread(workspace)
        let dots = scriptDots(workspace)
        return SidebarRowModel(
            workspace: workspace,
            title: workspaceTitle(workspace),
            statusKind: workspaceStatusKind(workspace, agents: rowAgents),
            selected: rowAgents.contains { $0.id == selectedAgentId },
            attention: rowAgents.contains { $0.requiresAttention == true } || manuallyUnread,
            manuallyUnread: manuallyUnread,
            hidden: isHiddenFromSidebar(workspace),
            firstAgentId: rowAgents.first?.id,
            branchText: workspace.branch ?? workspaceKindLabel(workspace),
            ageText: derivations.activityDates[workspace.id].map {
                relativeAge($0, now: derivations.now)
            },
            showBranch: showBranch,
            showDiffStats: showDiffStats,
            showPRBadge: showPRBadge,
            labelDefinitions: labelDefinitions(for: workspace, catalog: derivations.labelCatalog),
            scriptDots: dots,
            scriptDotsLabel: dots.isEmpty ? "" : scriptDotsLabel(workspace, count: dots.count),
            supportsPinning: derivations.supportsPinning,
            supportsLabels: derivations.supportsLabels,
            labelCatalog: derivations.labelCatalog)
    }

    /// One dot per script in trouble: green running, red when it exited non-zero. Live state from
    /// the terminals store when it has it, else the pushed descriptor payload.
    func scriptDots(_ workspace: WorkspaceDescriptor) -> [SidebarScriptDot] {
        let storeScripts = session.terminals.scripts(in: workspace.id)
        let scripts = storeScripts.isEmpty ? workspace.scripts : storeScripts
        var dots: [SidebarScriptDot] = []
        for script in scripts {
            if script.lifecycle == .running {
                dots.append(.running)
            } else if let code = script.exitCode, code != 0 {
                dots.append(.failed)
            }
        }
        return Array(dots.prefix(3))
    }

    func scriptDotsLabel(_ workspace: WorkspaceDescriptor, count: Int) -> String {
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

    func agents(
        in workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> [AgentSnapshot] {
        derivations.agentsByWorkspace[workspace.id] ?? []
    }

    /// One line: the workspace title, or the branch when there is no title.
    func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    /// "now", "5m", "3h", "2d", "4mo" — compact ages for the meta line.
    func relativeAge(_ date: Date, now: Date = Date()) -> String {
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

    /// Leading dot aggregated from the workspace's agents: permission → needs input, error →
    /// failed, running → working, finished-but-unseen → unread. Falls back to the workspace's own
    /// status bucket when no agent outranks it.
    func workspaceStatusKind(
        _ workspace: WorkspaceDescriptor, agents: [AgentSnapshot]
    ) -> StatusDot.State {
        if agents.contains(where: { $0.attention == .permission }) { return .attention }
        if agents.contains(where: { $0.attention == .error || $0.status == .error }) { return .failed }
        if agents.contains(where: { $0.status == .running }) { return .running }
        if agents.contains(where: { $0.attention == .finished }) { return .unread }
        return statusState(workspace.status)
    }

    /// A finished workspace is no longer a green dot (UX-SPEC §0.1 keeps green for diff
    /// counts), so `.done` reads as the quiet dot.
    func statusState(_ status: WorkspaceStatusBucket) -> StatusDot.State {
        switch status {
        case .needsInput, .attention: .attention
        case .failed: .failed
        case .running: .running
        case .done, .unknown: .idle
        }
    }

    func workspaceKindLabel(_ workspace: WorkspaceDescriptor) -> String {
        switch workspace.workspaceKind {
        case .worktree: "Worktree"
        case .checkout, .localCheckout: "Checkout"
        case .directory: "Project root"
        case .unknown: "Workspace"
        }
    }
}
#endif
