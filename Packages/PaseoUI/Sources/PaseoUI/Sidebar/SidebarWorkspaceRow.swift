#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension PaseoSidebar {
    func workspaceRow(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> some View {
        let rowAgents = agents(in: workspace, derivations: derivations)
        let selected = rowAgents.contains { $0.id == selectedAgentId }
        let attention = rowAgents.contains { $0.requiresAttention == true } || isManuallyUnread(workspace)
        return Button {
            openWorkspace(workspace, agents: rowAgents)
        } label: {
            HStack(spacing: 8) {
                StatusDot(workspaceStatusKind(workspace, agents: rowAgents))
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspaceTitle(workspace))
                        .font(.paseo(.callout, weight: .medium))
                        .lineLimit(1)
                    metaRow(workspace, derivations: derivations)
                }
                Spacer(minLength: 0)
                if attention {
                    StatusDot(.unread)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background(selected ? Palette.chip : Color.clear, in: .rect(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isManuallyUnread(workspace) ? "Manually marked unread" : (attention ? "Needs attention" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            // PLAN §RH order: open-variants, edit verbs, copy, hide, then the destructive verb.
            Button("New session", systemImage: "plus") { onNewSession(workspace.id) }
            Button("Rename…", systemImage: "pencil") {
                renameText = workspace.title ?? workspace.name
                renamingWorkspace = workspace
            }
            if session.workspaceDirectory.supportsWorkspacePinning {
                Button(
                    workspace.isPinned ? "Unpin" : "Pin",
                    systemImage: workspace.isPinned ? "pin.slash" : "pin"
                ) {
                    Task {
                        let ok = await session.workspaceDirectory.setPinned(
                            workspace.id, !workspace.isPinned)
                        if !ok {
                            showToast(
                                session.workspaceDirectory.actionError
                                    ?? "Couldn't change the pin.")
                        }
                    }
                }
            }
            Button(
                isManuallyUnread(workspace) ? "Clear unread mark" : "Mark as unread",
                systemImage: isManuallyUnread(workspace) ? "checkmark.circle" : "circle"
            ) {
                Haptics.selection()
                toggleManualUnread(workspace)
            }
            if session.labels.supportsLabels {
                Menu("Labels", systemImage: "tag") {
                    labelsSubmenu(for: workspace)
                }
            }
            Button("Copy path", systemImage: "doc.on.doc") {
                Clipboard.copy(workspace.cwd)
                showToast("Path copied")
            }
            if let branch = workspace.branch {
                Button("Copy branch name", systemImage: "doc.on.doc") {
                    Clipboard.copy(branch)
                    showToast("Branch name copied")
                }
            }
            Button(
                isHiddenFromSidebar(workspace) ? "Unhide" : "Hide",
                systemImage: isHiddenFromSidebar(workspace) ? "eye" : "eye.slash"
            ) {
                Haptics.selection()
                toggleHiddenFromSidebar(workspace)
            }
            Divider()
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                archive.request(workspace, session: session, toast: toast)
            }
        }
    }

    /// Tapping a workspace opens its most recently active agent; the other agents are the header's
    /// tab chips. Opening also clears a manual unread mark.
    func openWorkspace(_ workspace: WorkspaceDescriptor, agents: [AgentSnapshot]) {
        // The tap moves the drawer, so the shell owns the haptic (PLAN §RH).
        clearManualUnread(workspace)
        guard let target = agents.first else {
            // No agent yet: a draft in this workspace, like Search (audit C #6).
            onNewSession(workspace.id)
            return
        }
        onSelectAgent(target.id)
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

    @ViewBuilder func metaRow(
        _ workspace: WorkspaceDescriptor, derivations: SidebarDerivations
    ) -> some View {
        // Looked up once per row instead of up to three times (P5 finding #3).
        let activityStamp = derivations.activityDates[workspace.id]
        HStack(spacing: 4) {
            if showBranch {
                Text(workspace.branch ?? workspaceKindLabel(workspace))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            if showDiffStats, let stat = workspace.diffStat, stat.additions > 0 || stat.deletions > 0 {
                if showBranch { Text("·").foregroundStyle(Palette.captionInk) }
                if stat.additions > 0 {
                    Text("+\(PaseoFormat.integer(stat.additions))")
                        .foregroundStyle(Palette.successInk.opacity(0.75))
                }
                if stat.deletions > 0 {
                    Text("−\(PaseoFormat.integer(stat.deletions))")
                        .foregroundStyle(Palette.failureInk.opacity(0.75))
                }
            }
            if let stamp = activityStamp {
                if showBranch || hasVisibleDiffStat(workspace) {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                Text(relativeAge(stamp))
                    .foregroundStyle(Palette.secondaryInk)
            }
            let rowLabels = labelDefinitions(for: workspace)
            if !rowLabels.isEmpty {
                if showBranch || hasVisibleDiffStat(workspace) || activityStamp != nil {
                    Text("·").foregroundStyle(Palette.captionInk)
                }
                labelChips(for: workspace)
            }
            Spacer(minLength: 6)
            if showPRBadge, let pullRequest = pullRequest(workspace), let number = pullRequest.number {
                Text(verbatim: "#\(number)")
                    .font(.paseo(.caption2, weight: .semibold))
                    .foregroundStyle(pullRequestTint(workspace))
            }
            if case let dots = scriptDots(workspace), !dots.isEmpty {
                HStack(spacing: 3) {
                    ForEach(0..<dots.count, id: \.self) { index in
                        Circle().fill(dots[index]).frame(width: 5, height: 5)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(scriptDotsLabel(workspace, count: dots.count))
            }
        }
        .font(.paseo(.caption))
        .lineLimit(1)
    }

    func hasVisibleDiffStat(_ workspace: WorkspaceDescriptor) -> Bool {
        guard showDiffStats, let stat = workspace.diffStat else { return false }
        return stat.additions > 0 || stat.deletions > 0
    }

    /// The descriptor carries the PR summary (`githubRuntime.pullRequest`); per-checkout PR state
    /// (GitExtras) would need a checkout per row, which we don't want on a hot list.
    func pullRequest(_ workspace: WorkspaceDescriptor) -> WorkspaceGitHubRuntime.WorkspacePullRequest? {
        workspace.githubRuntime?.pullRequest
    }

    func pullRequestTint(_ workspace: WorkspaceDescriptor) -> Color {
        guard let pr = pullRequest(workspace) else { return Palette.secondaryInk }
        if pr.isMerged { return Palette.unread }
        if pr.isDraft == true { return Palette.tertiaryInk }
        switch pr.state.lowercased() {
        case "open": return Palette.successInk
        case "closed": return Palette.failureInk
        default: return Palette.secondaryInk
        }
    }

    /// One dot per script in trouble: green running, red when it exited non-zero. Live state from
    /// the terminals store when it has it, else the pushed descriptor payload.
    func scriptDots(_ workspace: WorkspaceDescriptor) -> [Color] {
        let storeScripts = session.terminals.scripts(in: workspace.id)
        let scripts = storeScripts.isEmpty ? workspace.scripts : storeScripts
        var dots: [Color] = []
        for script in scripts {
            if script.lifecycle == .running {
                dots.append(Palette.successInk)
            } else if let code = script.exitCode, code != 0 {
                dots.append(Palette.failureInk)
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
