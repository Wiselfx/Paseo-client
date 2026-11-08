#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The drawer: `WorkspaceDirectory` groups, project → workspace (name, branch, status) → agents.
/// Selecting an agent opens its conversation and clears its attention badge.
struct PaseoSidebar: View {
    let session: HostSession
    var selectedAgentId: String?
    var onSelectAgent: (String) -> Void
    var onClose: () -> Void
    var onDisconnect: () -> Void

    private let typography = ClaudeTypography()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Paseo").font(.custom(typography.serifName, size: 27))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                        .frame(width: 40, height: 40)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Close sidebar")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    directory
                    if !unplacedAgents.isEmpty {
                        sectionHeader("Other agents")
                        ForEach(unplacedAgents) { agent in agentRow(agent) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ClaudePalette.adaptive(light: 0.96, dark: 0.065))
        .onAppear {
            guard !session.workspaceDirectory.hasLoaded, session.workspaceDirectory.error == nil else { return }
            Task { await session.workspaceDirectory.refresh() }
        }
    }

    // MARK: Directory

    @ViewBuilder private var directory: some View {
        let groups = session.workspaceDirectory.groups
        if groups.isEmpty {
            if session.agents.isEmpty {
                Text(
                    session.workspaceDirectory.isLoading
                        ? "Loading workspaces…" : "No workspaces on this host yet."
                )
                .font(.system(size: 14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .padding(.vertical, 24)
            } else {
                sectionHeader("Agents")
                ForEach(session.agents) { agent in agentRow(agent) }
            }
        } else {
            ForEach(groups) { group in
                sectionHeader(group.project.projectCustomName ?? group.project.projectDisplayName)
                ForEach(group.workspaces) { workspace in
                    workspaceRow(workspace)
                    ForEach(agents(in: workspace)) { agent in agentRow(agent) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ClaudePalette.tertiaryInk)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func workspaceRow(_ workspace: WorkspaceDescriptor) -> some View {
        HStack(spacing: 8) {
            PaseoStatusDot(kind: statusKind(workspace.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(workspace.gitRuntime?.currentBranch ?? workspaceKindLabel(workspace))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func agents(in workspace: WorkspaceDescriptor) -> [AgentSnapshot] {
        session.agents.filter { $0.workspaceId == workspace.id }
    }

    private var unplacedAgents: [AgentSnapshot] {
        let known = Set(session.workspaceDirectory.workspaces.map(\.id))
        return session.agents.filter { agent in
            guard let workspaceId = agent.workspaceId else { return true }
            return !known.contains(workspaceId)
        }
    }

    // MARK: Agents

    private func agentRow(_ agent: AgentSnapshot) -> some View {
        let selected = agent.id == selectedAgentId
        return Button {
            Haptics.selection()
            onSelectAgent(agent.id)
        } label: {
            HStack(spacing: 8) {
                PaseoStatusDot(kind: agentStatusKind(agent))
                Text(agent.title ?? "New agent")
                    .font(.system(size: 15, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if agent.status == .running, agent.requiresAttention != true {
                    PaseoStatusDot(kind: .running)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 38)
            .foregroundStyle(ClaudePalette.ink)
            .contentShape(.rect)
            .background(selected ? ClaudePalette.chip : Color.clear, in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(agent.title ?? "New agent")
        .accessibilityValue(agent.requiresAttention == true ? "Needs attention" : "")
    }

    private func statusKind(_ status: WorkspaceStatusBucket) -> PaseoStatusDot.Kind {
        switch status {
        case .needsInput, .attention: .needsInput
        case .failed: .failed
        case .running: .running
        case .done: .done
        case .unknown: .idle
        }
    }

    private func agentStatusKind(_ agent: AgentSnapshot) -> PaseoStatusDot.Kind {
        switch agent.attention {
        case .permission: return .needsInput
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        switch agent.status {
        case .running: return .running
        case .error: return .failed
        case .initializing, .idle, .closed, .unknown: return .idle
        }
    }

    private func workspaceKindLabel(_ workspace: WorkspaceDescriptor) -> String {
        switch workspace.workspaceKind {
        case .worktree: "Worktree"
        case .checkout, .localCheckout: "Checkout"
        case .directory: "Project root"
        case .unknown: "Workspace"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            PaseoStatusDot(kind: connectionKind)
            Text(session.serverInfo?.hostname ?? "Paseo daemon")
                .font(.system(size: 13))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(1)
            Spacer(minLength: 0)
            Menu {
                Button("Disconnect", systemImage: "bolt.horizontal.circle", role: .destructive) { onDisconnect() }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Host options")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var connectionKind: PaseoStatusDot.Kind {
        switch session.connection {
        case .connected: .done
        case .reconnecting, .connecting: .running
        case .failed: .failed
        case .idle: .idle
        }
    }
}

/// 6 pt dot: breathing while running, yellow for input, blue for unread, hollow for idle.
struct PaseoStatusDot: View {
    enum Kind: Equatable { case running, needsInput, failed, done, unread, idle }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Group {
            switch kind {
            case .running:
                Circle().fill(ClaudePalette.secondaryInk).frame(width: 6, height: 6)
                    .opacity(breathing ? 1 : 0.3)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: breathing)
                    .onAppear { breathing = true }
            case .needsInput: Circle().fill(ClaudePalette.warning).frame(width: 6, height: 6)
            case .failed: Circle().fill(ClaudePalette.failureInk).frame(width: 6, height: 6)
            case .done: Circle().fill(ClaudePalette.successInk).frame(width: 6, height: 6)
            case .unread: Circle().fill(ClaudePalette.unread).frame(width: 6, height: 6)
            case .idle: Circle().strokeBorder(ClaudePalette.captionInk, lineWidth: 1).frame(width: 6, height: 6)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}
#endif
