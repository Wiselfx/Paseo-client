import Foundation

// Owned subscriptions: the modern subscription protocol.
//
// Source: packages/protocol/src/client-capabilities.ts `CLIENT_CAPS.ownedSubscriptions`
// (`owned_subscriptions`, added in daemon v0.8.0) and `CLIENT_CAPS.workspaceSetupObservation`
// (`workspace_setup_observation`). Source: packages/server/src/server/session.ts:1372 — the
// daemon marks a socket `modern` from the hello capability alone; every subscription the socket
// opens afterwards is owned by it and carries a server-assigned `subscriptionId`.
// See `docs/research/09-owned-subscriptions.md` for the full wire contract.
//
// Advertising the capability is all-or-nothing: a modern socket receives *only* frames that were
// emitted by one of its own subscriptions (plus the hello response). Broadcasts stop. Every
// subscription path therefore has to be implemented before the flag flips on.

/// Client capabilities and the single switch for the owned-subscription protocol.
public enum OwnedSubscriptions {
    /// `owned_subscriptions`. Source: `client-capabilities.ts` `CLIENT_CAPS.ownedSubscriptions`.
    public static let capability = "owned_subscriptions"
    /// `features.ownedSubscriptions` in `server_info` (camelCase, unlike the capability name).
    /// Source: `packages/server/src/server/websocket-server.ts:2029`.
    public static let feature = "ownedSubscriptions"
    /// `workspace_setup_observation`. The daemon gates `workspace.setup.subscribe.request` on it
    /// (`session.ts:2480-2490`), and stops broadcasting `workspace_setup_progress` to clients that
    /// advertise it (`session.ts:9000-9012`).
    public static let setupObservationCapability = "workspace_setup_observation"

    /// The one switch. When `false` the hello omits `owned_subscriptions` and
    /// `workspace_setup_observation`, the daemon keeps every legacy broadcast path, and the
    /// stores keep the legacy detach/release RPCs. Flip this to `false` and rebuild if a daemon
    /// misbehaves with subscriptions; nothing else needs to change.
    public static let isEnabled = true
}

extension ServerInfo {
    /// Whether this connection speaks the owned-subscription protocol: the daemon advertises
    /// `features.ownedSubscriptions` *and* this client advertised the matching hello capability.
    /// Read once per connection; stores branch on it, views never do.
    public var supportsOwnedSubscriptions: Bool {
        OwnedSubscriptions.isEnabled && hasFeature(OwnedSubscriptions.feature)
    }
}
