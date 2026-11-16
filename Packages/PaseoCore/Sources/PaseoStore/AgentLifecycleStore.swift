import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Live + archived agent history, page by page; rename / archive / unarchive / permanent delete.
/// Independent of `HostSession.agents`, which drops archived entries at ingest — this store
/// keeps its own merged view so the History screen can show them.
///
/// IMPLEMENTATION TICKET: docs/tickets/M7e-agent-lifecycle.md
@MainActor @Observable
public final class AgentLifecycleStore {
    public enum LoadPhase: Sendable, Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: LoadPhase = .idle
    /// Everything the source reported, newest first: live and archived mixed.
    public private(set) var entries: [AgentSnapshot] = []
    public private(set) var error: String?
    public private(set) var nextCursor: String?
    public private(set) var hasMore = false
    public private(set) var isLoadingMore = false
    /// True while one mutation (rename / archive / unarchive / delete) is in flight.
    public private(set) var isWorking = false
    public private(set) var actionError: String?

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    /// Loads the first page (newest first, live + archived), replacing what we hold.
    public func load() async {
        phase = .loading
        error = nil
        do {
            let response = try await client.send(FetchAgentHistoryRequest(page: .init(limit: 50)))
            entries = response.entries.map(\.agent)
            nextCursor = response.pageInfo.nextCursor
            hasMore = response.pageInfo.hasMore
            phase = .ready
        } catch let caught {
            let message = paseoStoreErrorText(caught)
            self.error = message
            phase = .failed(message)
        }
    }

    /// Fetches the next page (cursor-based) and appends, de-duplicated by id.
    public func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await client.send(
                FetchAgentHistoryRequest(page: .init(limit: 50, cursor: cursor)))
            let existing = Set(entries.map(\.id))
            let incoming = response.entries.map(\.agent).filter { !existing.contains($0.id) }
            entries += incoming
            nextCursor = response.pageInfo.nextCursor
            hasMore = response.pageInfo.hasMore
        } catch let caught {
            error = paseoStoreErrorText(caught)
        }
    }

    /// Brings an archived agent back to life (`refresh_agent_request`, the upstream unarchive).
    /// The entry is flipped to live locally.
    @discardableResult
    public func unarchive(agentId: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(RefreshAgentRequest(agentId: agentId))
            patch(agentId) { $0.archivedAt = nil }
            actionError = nil
            return true
        } catch let caught {
            actionError = paseoStoreErrorText(caught)
            return false
        }
    }

    /// Archives (soft-deletes) the agent. The entry is flipped to archived locally.
    @discardableResult
    public func archive(agentId: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await client.send(ArchiveAgentRequest(agentId: agentId))
            patch(agentId) { $0.archivedAt = response.archivedAt }
            actionError = nil
            return true
        } catch let caught {
            actionError = paseoStoreErrorText(caught)
            return false
        }
    }

    /// Permanently deletes the agent (`delete_agent_request` → `agent_deleted`).
    @discardableResult
    public func delete(agentId: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(DeleteAgentRequest(agentId: agentId))
            entries.removeAll { $0.id == agentId }
            actionError = nil
            return true
        } catch let caught {
            actionError = paseoStoreErrorText(caught)
            return false
        }
    }

    /// Promotes a managed subagent to a standalone agent (`agent.detach.request`): the daemon
    /// clears its `paseo.parent-agent-id` label, so it stops appearing under its parent. The
    /// label change itself arrives on the usual `agent_update` stream. Hosts without
    /// `features.agentDetach` reject the request; the message is surfaced in `actionError`.
    @discardableResult
    public func detach(agentId: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await client.send(AgentDetachRequest(agentId: agentId))
            guard response.accepted else {
                actionError = response.error ?? "The daemon rejected the detach."
                return false
            }
            patch(agentId) { $0.labels?.removeValue(forKey: AgentParentLabel.agentId) }
            actionError = nil
            return true
        } catch let caught {
            actionError = paseoStoreErrorText(caught)
            return false
        }
    }

    /// Marks this client's `paseo.open-agent-tab.<client-id>` label on a managed subagent while
    /// its tab is open, or clears it when the tab closes or the app leaves the foreground.
    ///
    /// The daemon resolves a parent's archive by detaching children with any `true` open-tab
    /// label and cascade-archiving the rest, so this label is what keeps an agent the user is
    /// looking at alive. Upstream: docs/agent-lifecycle.md:130-134,
    /// packages/protocol/src/agent-labels.ts:4-7,
    /// packages/app/src/screens/workspace/workspace-screen.tsx:2028-2034, 2330-2336.
    ///
    /// The client id is the one this connection already sent in its hello, never a new one: the
    /// daemon keys the label per client. A test double has none and writes nothing. A failed
    /// marker is swallowed on purpose: it is background bookkeeping, not a user action, and a
    /// banner about it would replace whatever the screen is actually saying.
    public func setOpenAgentTab(agentId: String, open: Bool) async {
        guard let clientId = (client as? DaemonConnection)?.clientId else { return }
        let label = "paseo.open-agent-tab.\(clientId)"
        _ = try? await client.send(
            UpdateAgentRequest(agentId: agentId, labels: [label: open ? "true" : "false"]))
    }

    /// Renames the agent (`update_agent_request`).
    @discardableResult
    public func rename(agentId: String, to name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            actionError = "A name is required."
            return false
        }
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.send(UpdateAgentRequest(agentId: agentId, name: trimmed))
            patch(agentId) { $0.title = trimmed }
            actionError = nil
            return true
        } catch let caught {
            actionError = paseoStoreErrorText(caught)
            return false
        }
    }

    private func patch(_ agentId: String, _ mutate: (inout AgentSnapshot) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == agentId }) else { return }
        var entry = entries[index]
        mutate(&entry)
        entries[index] = entry
    }
}
