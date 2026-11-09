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
                    parentAgentId: agentId, subagentId: subagentId, direction: .tail, limit: limit))
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
        guard messageType == "agent.provider_subagents.update", isSupported else { return false }
        guard
            let update = try? JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: raw
            ).payload
        else { return false }

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
