#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

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
                    SidebarRowMetaLine(model: model)
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
        .accessibilityValue(spokenValue)
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
                    SidebarRowLabelsMenu(model: model, actions: actions)
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

    /// What the row's dot and PR badge say with color alone: the aggregate status, the unread or
    /// attention flag, and the pull request's state. The dot is hidden from VoiceOver.
    private var spokenValue: String {
        let flag: String? =
            model.manuallyUnread
            ? String(localized: "Manually marked unread", bundle: #bundle)
            : (model.attention ? String(localized: "Needs attention", bundle: #bundle) : nil)
        return [statusSpokenName, flag, pullRequestSpokenState].compactMap { $0 }.formatted()
    }

    private var statusSpokenName: String? {
        switch model.statusKind {
        case .running: String(localized: "Running", bundle: #bundle)
        case .attention: String(localized: "Needs input", bundle: #bundle)
        case .failed: String(localized: "Failed", bundle: #bundle)
        case .unread: String(localized: "Unread", bundle: #bundle)
        case .idle: nil
        }
    }

    /// Mirrors `SidebarRowMetaLine.pullRequestTint`, which is the badge's only state cue; nil when the badge is off.
    private var pullRequestSpokenState: String? {
        guard model.showPRBadge, let pullRequest = model.workspace.githubRuntime?.pullRequest,
            pullRequest.number != nil
        else { return nil }
        if pullRequest.isMerged { return String(localized: "Pull request merged", bundle: #bundle) }
        if pullRequest.isDraft == true {
            return String(localized: "Pull request draft", bundle: #bundle)
        }
        switch pullRequest.state.lowercased() {
        case "open": return String(localized: "Pull request open", bundle: #bundle)
        case "closed": return String(localized: "Pull request closed", bundle: #bundle)
        default: return nil
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
        let running = scripts.count(where: { $0.lifecycle == .running })
        let crashed = scripts.count(where: { $0.lifecycle != .running && ($0.exitCode ?? 0) != 0 })
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if crashed > 0 { parts.append("\(crashed) exited") }
        return "Scripts: " + (parts.isEmpty ? "\(count)" : parts.formatted())
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
