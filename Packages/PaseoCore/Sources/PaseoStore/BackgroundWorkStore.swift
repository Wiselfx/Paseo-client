import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// M7g: background shells/monitors the agent has running.
//
// The list is gated on `features.agentBackgroundWork` and stop on
// `features.agentBackgroundWorkStop`; a daemon without the gates refuses every
// background-work request with `rpc_error` / `unknown_schema`, which does not settle a
// pending request, so the store refuses the RPC client-side when the gate reads false.

@MainActor @Observable
public final class BackgroundWorkStore {
    /// The current items, in the daemon's order; every push replaces the whole list.
    public private(set) var items: [BackgroundWorkItem] = []
    public private(set) var isLoading = false
    /// Last failure, for the row's fine print. Cleared by the next successful load/push.
    public private(set) var error: String?
    /// Host gate: `server_info.features.agentBackgroundWork`.
    public private(set) var isSupported = false
    /// Stop gate: `server_info.features.agentBackgroundWorkStop`.
    public private(set) var canStop = false

    /// The wire type this store follows.
    static let messageType = "agent.background_work.update"
    /// Shared by every pushed update; `JSONDecoder` is safe for sequential use on the main actor.
    private static let decoder = JSONDecoder()

    private let agentId: String
    private let client: (any DaemonClient)?

    init(agentId: String, client: (any DaemonClient)?) {
        self.agentId = agentId
        self.client = client
    }

    public var hasRunningItems: Bool { !items.isEmpty }

    /// Refetches the whole list. Safe to call on open and reconnect — pushes keep it live.
    public func load() async {
        guard isSupported, let client else {
            if !isSupported { items = [] }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.send(BackgroundWorkListRequest(agentId: agentId))
            if let message = response.error {
                error = message
                return
            }
            items = response.items
            error = nil
        } catch let cause {
            error = conversationErrorText(cause)
        }
    }

    /// Stops one item; nil on success (or optimistic removal), the refusal otherwise.
    /// The UI confirms for running shells before calling.
    public func stop(itemId: String) async -> String? {
        guard canStop else {
            return "Background work stop is not supported on this host."
        }
        guard let item = items.first(where: { $0.id == itemId }) else {
            return "That task is no longer running."
        }
        guard item.canStop == true, let stopToken = item.stopToken else {
            return "This task can't be stopped."
        }
        guard let client else {
            return "This conversation is not connected to a daemon."
        }
        do {
            let response = try await client.send(
                BackgroundWorkStopRequest(agentId: agentId, itemId: itemId, stopToken: stopToken))
            if let message = response.error {
                error = message
                return message
            }
            // Optimistic removal; the next push reconciles.
            items.removeAll { $0.id == itemId }
            error = nil
            return nil
        } catch let cause {
            let message = conversationErrorText(cause)
            error = message
            return message
        }
    }

    /// Called once per `server_info`; the gates are read here only.
    internal func update(serverInfo info: ServerInfo?) {
        guard let info else { return }
        isSupported = info.hasFeature("agentBackgroundWork")
        canStop = info.hasFeature("agentBackgroundWorkStop")
        if !isSupported {
            items = []
        }
    }

    /// Routes one unsolicited message; returns true when it belonged to this feature.
    internal func handle(messageType: String, raw: Data) -> Bool {
        guard messageType == Self.messageType, isSupported else { return false }
        guard
            let update = try? Self.decoder.decode(
                SessionPayloadEnvelope<BackgroundWorkUpdate>.self, from: raw).payload
        else { return true }
        return apply(update)
    }

    /// Applies one pushed update that `HostSession` already decoded once and routed by agent.
    internal func apply(_ update: BackgroundWorkUpdate) -> Bool {
        guard isSupported else { return false }
        guard update.agentId == agentId else { return true }
        items = update.items
        error = nil
        return true
    }
}

extension ConversationStore {
    /// Called once per `server_info` and when a conversation opens. Widened from T12.
    internal func reloadBackgroundWork() async {
        await backgroundWork.load()
    }

    /// Routes one unsolicited message; ignores parents that are not ours. Widened from T12.
    internal func handleBackgroundWorkUpdate(messageType: String, raw: Data) {
        _ = backgroundWork.handle(messageType: messageType, raw: raw)
    }

    /// Applies one pushed background-work update already decoded by `HostSession`.
    internal func handleBackgroundWorkUpdate(_ update: BackgroundWorkUpdate) {
        _ = backgroundWork.apply(update)
    }
}
