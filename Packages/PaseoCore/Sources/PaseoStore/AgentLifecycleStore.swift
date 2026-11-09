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
