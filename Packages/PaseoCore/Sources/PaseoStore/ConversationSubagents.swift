import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Provider-managed subagents for one parent agent. Provider rows are read-only.
///
/// Owned by `ConversationStore` as `subagents`. The list is refetched on open and after a
/// reconnect, because update events are not replayed; live `agent.provider_subagents.update`
/// events keep it current in between.
@MainActor @Observable
public final class ConversationSubagents {
    /// Plain capability flag read once from `server_info.features.providerSubagents`.
    public private(set) var isSupported = true
    /// In the daemon's order, with upserts replacing in place.
    public private(set) var items: [ProviderSubagent] = []
    public private(set) var isLoading = false
    /// Last list or event failure, for the subagent track. Cleared by the next successful load.
    public private(set) var error: String?

    /// The wire type this store follows.
    static let messageType = "agent.provider_subagents.update"
    /// Shared by every pushed update; `JSONDecoder` is safe for sequential use on the main actor.
    private static let decoder = JSONDecoder()

    private let agentId: String
    private let client: (any DaemonClient)?

    init(agentId: String, client: (any DaemonClient)?) {
        self.agentId = agentId
        self.client = client
    }

    /// Subagents still working.
    public var active: [ProviderSubagent] { items.filter { $0.status == .running } }

    public func subagent(id: String) -> ProviderSubagent? { items.first { $0.id == id } }

    /// Refetches the whole list. Safe to call repeatedly (opening, pull, reconnect).
    public func load() async {
        guard isSupported else {
            items = []
            error = nil
            return
        }
        guard let client else {
            error = "This conversation is not connected to a daemon."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.send(ProviderSubagentListRequest(parentAgentId: agentId))
            guard response.parentAgentId == agentId else { return }
            if let message = response.error {
                error = message
                return
            }
            items = response.subagents
            error = nil
        } catch let cause {
            error = conversationErrorText(cause)
        }
    }

    /// One tail page of a provider subagent's timeline, read-only. Sets `error` and returns nil
    /// on failure. Never advances the parent's list; rows are the same projected
    /// `TimelineEntry`s the main timeline uses.
    public func timelinePage(
        for subagentId: String, limit: Int = 50
    ) async -> ProviderSubagentTimelineRequest.Response? {
        await timeline(subagentId: subagentId, direction: .tail, cursor: nil, limit: limit)
    }

    /// The page before `cursor` (`E3b`): the sheet prepends it when the reader reaches the top.
    /// The same read-only path as the tail page; the response carries the new `startCursor` and
    /// `hasOlder`.
    public func timelinePage(
        for subagentId: String, before cursor: TimelineCursor, limit: Int = 50
    ) async -> ProviderSubagentTimelineRequest.Response? {
        await timeline(subagentId: subagentId, direction: .before, cursor: cursor, limit: limit)
    }

    private func timeline(
        subagentId: String, direction: ProviderSubagentTimelineRequest.Direction,
        cursor: TimelineCursor?, limit: Int
    ) async -> ProviderSubagentTimelineRequest.Response? {
        guard isSupported else {
            error = "This provider does not support subagents."
            return nil
        }
        guard let client else {
            error = "This conversation is not connected to a daemon."
            return nil
        }
        do {
            let response = try await client.send(
                ProviderSubagentTimelineRequest(
                    parentAgentId: agentId, subagentId: subagentId, direction: direction,
                    cursor: cursor, limit: limit))
            if let message = response.error {
                error = message
                return nil
            }
            error = nil
            return response
        } catch {
            self.error = conversationErrorText(error)
            return nil
        }
    }

    /// Called from `HostSession` once per `server_info`; the capability is read here only.
    internal func update(serverInfo info: ServerInfo?) {
        guard let info else { return }
        isSupported = info.hasFeature("providerSubagents")
        if !isSupported { items = [] }
    }

    /// Routes one unsolicited message. Returns true when it belonged to this feature.
    internal func handle(messageType: String, raw: Data) -> Bool {
        guard messageType == Self.messageType, isSupported else { return false }
        guard
            let update = try? Self.decoder.decode(
                SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: raw
            ).payload
        else { return false }
        return apply(update)
    }

    /// Applies one pushed update that `HostSession` already decoded once and routed by parent.
    /// Pushes for another parent are ignored here too, so the store is safe on its own.
    internal func apply(_ update: ProviderSubagentUpdate) -> Bool {
        guard isSupported else { return false }
        switch update.kind {
        case .upsert(let subagent):
            guard subagent.parentAgentId == agentId else { return true }
            if let index = items.firstIndex(where: { $0.id == subagent.id }) {
                items[index] = subagent
            } else {
                items.append(subagent)
            }
            error = nil

        case .remove(let removal):
            guard removal.parentAgentId == agentId else { return true }
            items.removeAll { $0.id == removal.subagentId }

        case .timeline, .unknown:
            break
        }
        return true
    }
}

extension ConversationStore {
    /// Applies one pushed subagent update already decoded by `HostSession`.
    internal func handleSubagentUpdate(_ update: ProviderSubagentUpdate) {
        _ = subagents.apply(update)
    }
}
