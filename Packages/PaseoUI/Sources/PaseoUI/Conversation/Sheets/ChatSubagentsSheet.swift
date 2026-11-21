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

    /// Upstream gates Detach on `features.agentDetach` (`panels/agent-tracks.tsx:67`).
    private var canDetach: Bool {
        session.serverInfo?.hasFeature("agentDetach") == true
    }

    var body: some View {
        // Derived once per pass: each is a filter (and `managed` a sort) the rows below would
        // otherwise repeat on every `ForEach` iteration.
        let items = subagents.items.filter { !hiddenIds.contains($0.id) }
        // Paseo-managed child agents, oldest first like upstream's track (`select.ts` sorts by
        // `createdAt`); they are ordinary agents, so they never appear in `subagents.items`.
        let managed = session.subagents(of: parentAgentId)
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let lastManagedID = managed.last?.id
        let lastItemID = items.last?.id
        let finishedCount = items.count(where: { $0.status != .running })
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
                                ManagedSubagentRow(
                                    agent: agent, providerLabel: providerLabel(agent),
                                    canDetach: canDetach, isDetaching: detachingId == agent.id,
                                    onOpen: onOpenAgent, onDetach: { detachTarget = agent })
                                if agent.id != lastManagedID || !items.isEmpty {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            ForEach(items) { item in
                                ProviderSubagentRow(item: item) { pushTarget = item }
                                if item.id != lastItemID {
                                    ClaudeDivider().padding(.leading, 44)
                                }
                            }
                            if let error = detachError ?? subagents.error {
                                InlineBanner(.failure, title: error)
                                    .padding(.horizontal, Space.lg)
                                    .padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, Space.xs)
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

    private func providerLabel(_ agent: AgentSnapshot) -> String {
        session.agentControl.provider(agent.provider)?.label ?? agent.provider
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
}
#endif
