import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// The socket-wide event subscription for pushes that are not part of a directory feed.
//
// On a modern socket (`owned_subscriptions`) the daemon delivers these messages only to clients
// that asked for them with `session.events.set_subscription.request`; the implicit broadcast path
// returns false for a modern source (`packages/server/src/server/session.ts:9000-9018`
// `wantsEvent`, and `:9060-9103` `emitSubscribedEvent`). On legacy sockets they still arrive as
// broadcasts, so this store does nothing there.
//
// See `docs/research/09-owned-subscriptions.md`.

/// The events this client consumes outside its terminal, workspace, label, agent, timeline, diff,
/// file and setup subscriptions. Names match `sessionEventCategory` in `session.ts`.
@MainActor @Observable
public final class OwnedEventSubscription {
    /// The event names every daemon that understands owned subscriptions accepts. The daemon's
    /// schema is a closed enum (`messages.ts:3359-3378`), and one unknown name rejects the whole
    /// request, so only names that shipped with the protocol go here. `status.daemon_config_changed`
    /// is how `HostSettingsStore` learns about config changes on a modern socket.
    public static let baseEvents = [
        "providers_snapshot_update",
        "agent_attention_required",
        "agent_permission_request",
        "agent_permission_resolved",
        "script_status_update",
        "terminal_attention_required",
        "agent.provider_subagents.update",
        "status.daemon_config_changed",
    ]

    /// The event names for this connection. `agent.background_work.update` is newer than the
    /// capability itself, so it is added only when the daemon advertises `agentBackgroundWork`.
    public private(set) var events = baseEvents

    /// True when this connection speaks owned subscriptions (daemon feature + our hello).
    public private(set) var isSupported = false
    /// The server-assigned subscription id, nil on legacy sockets or before the first connect.
    public private(set) var subscriptionId: String?
    /// Last failure to subscribe, for diagnostics. Advisory: the other stores keep working.
    public private(set) var error: String?

    private let client: any DaemonClient

    public init(client: any DaemonClient) {
        self.client = client
    }

    internal func update(serverInfo: ServerInfo?) {
        isSupported = serverInfo?.supportsOwnedSubscriptions ?? false
        var events = Self.baseEvents
        if serverInfo?.hasFeature("agentBackgroundWork") == true {
            events.append("agent.background_work.update")
        }
        self.events = events
    }

    /// Subscribes on every `.connected`. The daemon drops all subscriptions with the socket, so a
    /// reconnect always needs a fresh request.
    internal func connected() async {
        guard isSupported else {
            subscriptionId = nil
            return
        }
        do {
            // `notifications: true` is what lets the daemon keep `shouldNotify` set for this
            // source (`session.ts:9031-9054` `emitEventToOwner`): without it every attention
            // event arrives with `shouldNotify: false` and `AttentionCenter` drops it.
            let response = try await client.send(
                SessionEventsSetSubscriptionRequest(events: events, notifications: true))
            subscriptionId = response.subscriptionId
            error = nil
        } catch {
            subscriptionId = nil
            self.error = paseoStoreErrorText(error)
        }
    }

    /// Drops the id. There is nothing to release on a dead socket.
    internal func disconnected() {
        subscriptionId = nil
    }
}
