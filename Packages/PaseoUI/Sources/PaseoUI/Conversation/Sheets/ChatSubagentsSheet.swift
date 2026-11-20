#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The sheet that lists subagents. Managed rows (ordinary agents labelled with this parent,
/// `session.subagents(of:)`) open their conversation and can be detached; provider rows are
/// read-only and open a timeline. "Archive finished" hides every non-running provider row for
/// this session (app-side only, in memory — provider rows die with the provider session).
struct ChatSubagentsSheet: View {
    let session: HostSession
    let parentAgentId: String
    let subagents: ConversationSubagents
    @Binding var hiddenIds: Set<String>
    /// Opens a managed subagent in the shell; the caller dismisses the sheet.
    var onOpenAgent: (String) -> Void

    @State private var pushTarget: ProviderSubagent?
    @State private var detachTarget: AgentSnapshot?
    @State private var detachingId: String?
    @State private var detachError: String?

    /// Upstream `resolveSubagentLabel` (`subagents/detach-subagent.ts`): a blank title, or the
    /// "new agent" placeholder, names nothing, so the dialog says "This subagent".
    static func detachLabel(_ agent: AgentSnapshot) -> String {
        let trimmed = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "new agent" else {
            return "This subagent"
        }
        return trimmed
    }

    private var items: [ProviderSubagent] {
        subagents.items.filter { !hiddenIds.contains($0.id) }
    }

    /// Paseo-managed child agents, oldest first like upstream's track (`select.ts` sorts by
    /// `createdAt`); they are ordinary agents, so they never appear in `subagents.items`.
    private var managed: [AgentSnapshot] {
        session.subagents(of: parentAgentId)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Upstream gates Detach on `features.agentDetach` (`panels/agent-tracks.tsx:67`).
    private var canDetach: Bool {
        session.serverInfo?.hasFeature("agentDetach") == true
    }

    private var finishedCount: Int {
        items.filter { $0.status != .running }.count
    }

    var body: some View {
        SheetScaffold("Subagents", detents: .mediumLarge) {
            Group {
                if subagents.isLoading && items.isEmpty {
                    LoadingState()
                } else if items.isEmpty && managed.isEmpty {
                    EmptyState(
                        systemImage: "person.2",
                        title: "No subagents",
                        message: "Subagents your provider runs for this agent appear here."
                    )
                    .padding(.horizontal, 40)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(managed) { agent in
                                managedRow(agent)
                                if agent.id != managed.last?.id || !items.isEmpty {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            ForEach(items) { item in
                                subagentRow(item)
                                if item.id != items.last?.id {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            if let error = detachError ?? subagents.error {
                                InlineBanner(.failure, title: error)
                                    .padding(.horizontal, Space.lg)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if finishedCount > 0 {
                    VStack(spacing: 0) {
                        ClaudeDivider()
                        Button("Hide finished") {
                            hiddenIds.formUnion(items.filter { $0.status != .running }.map(\.id))
                        }
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(.rect)
                    }
                    .background(Palette.panel)
                }
            }
            .navigationDestination(item: $pushTarget) { subagent in
                ChatSubagentTimelineView(
                    subagents: subagents, subagent: subagent)
            }
            .confirmationDialog(
                "Detach subagent?",
                item: $detachTarget,
                titleVisibility: .visible
            ) { agent in
                // Upstream's confirm is not destructive: detaching loses nothing.
                Button("Detach") {
                    detachTarget = nil
                    Task { await detach(agent) }
                }
                Button("Cancel", role: .cancel) { detachTarget = nil }
            } message: { agent in
                Text(
                    "\(Self.detachLabel(agent)) will leave this track and continue as a standalone agent."
                )
            }
            .task { await subagents.load() }
        }
    }

    private func subagentRow(_ item: ProviderSubagent) -> some View {
        Button {
            pushTarget = item
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(SubagentStatusWord.dot(item.status))
                    .frame(width: 8, height: 8)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(item))
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle = rowSubtitle(item) {
                        Text(subtitle)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(SubagentStatusWord.label(item.status))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rowTitle(item)), \(SubagentStatusWord.label(item.status))")
    }

    /// A managed subagent: ordinary agent row plus the detach action. Upstream shows the action
    /// cluster always on compact form factors (a phone) and on hover on desktop
    /// (`subagents-track.tsx`, `actionsAlwaysVisible`), so the button is visible here; the context
    /// menu carries the same action for a long press.
    private func managedRow(_ agent: AgentSnapshot) -> some View {
        HStack(spacing: 12) {
            StatusDot(managedStatus(agent))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(managedTitle(agent))
                    .font(.paseo(.callout, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(providerLabel(agent))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if canDetach {
                if detachingId == agent.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel("Detaching")
                } else {
                    Button {
                        detachTarget = agent
                    } label: {
                        Image(systemName: "person.badge.minus")
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(Palette.secondaryInk)
                            .frame(width: 28, height: 28)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Detach \(managedTitle(agent))")
                    .accessibilityIdentifier("subagents.detach")
                }
            }
            Image(systemName: "chevron.right")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(.rect)
        .onTapGesture {
            onOpenAgent(agent.id)
        }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("Open agent", systemImage: "arrow.up.right.square") {
                onOpenAgent(agent.id)
            }
            if canDetach {
                Button("Detach", systemImage: "person.badge.minus") {
                    detachTarget = agent
                }
            }
        }
    }

    private func managedTitle(_ agent: AgentSnapshot) -> String {
        let trimmed = agent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "New agent" : trimmed
    }

    private func providerLabel(_ agent: AgentSnapshot) -> String {
        session.agentControl.provider(agent.provider)?.label ?? agent.provider
    }

    /// The same dot the panel's agent rows use: attention first, then the lifecycle status.
    private func managedStatus(_ agent: AgentSnapshot) -> StatusDot.State {
        switch agent.attention {
        case .permission: return .attention
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        return switch agent.status {
        case .running: .running
        case .error: .failed
        case .initializing, .idle, .closed, .unknown: .idle
        }
    }

    /// Detach, then open the agent: upstream's `requestDetachSubagent` opens the detached agent
    /// and reports a failure through the toast. Here the failure lands in the sheet's error line.
    private func detach(_ agent: AgentSnapshot) async {
        detachingId = agent.id
        detachError = nil
        let detached = await session.agentLifecycle.detach(agentId: agent.id)
        detachingId = nil
        guard detached else {
            detachError = session.agentLifecycle.actionError ?? "The detach failed."
            return
        }
        // The label is gone on the daemon; refresh so the row leaves this list and the agent
        // list stops nesting it.
        await session.refreshAgents()
        Haptics.success()
        onOpenAgent(agent.id)
    }

    private func rowTitle(_ item: ProviderSubagent) -> String {
        item.title ?? item.description ?? item.provider
    }

    private func rowSubtitle(_ item: ProviderSubagent) -> String? {
        if item.title != nil {
            return item.description ?? item.subtitle
        }
        return item.subtitle
    }
}
#endif
