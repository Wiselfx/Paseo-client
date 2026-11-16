import Foundation
import PaseoKit
import PaseoProtocol

// Owned-subscription helpers shared by the stores.
//
// On a modern socket (`owned_subscriptions` advertised in the hello) every subscription is
// owned by the socket and gets a server-assigned `subscriptionId`. It is released with
// `subscription.release.request` (`packages/server/src/server/session.ts:2533-2542`), not with
// the legacy per-family unsubscribe RPCs, which throw on modern sockets
// (`session/owned-subscriptions/index.ts:391-400`).
//
// See `docs/research/09-owned-subscriptions.md`.

extension DaemonClient {
    /// Releases a server-assigned owned subscription. No-op for nil or an empty id. Never throws:
    /// a dead socket reconnects on its own and the daemon drops every subscription with it.
    func releaseOwnedSubscription(_ subscriptionId: String?) async {
        guard let subscriptionId, !subscriptionId.isEmpty else { return }
        _ = try? await send(
            SubscriptionReleaseRequest(subscriptionId: subscriptionId),
            timeout: .milliseconds(500))
    }

    /// Sends a legacy per-family unsubscribe when the daemon handed out no subscription id, and
    /// a modern release when it did. `subscriptionId` comes from the wire, so the branch matches
    /// whatever protocol this socket actually negotiated.
    func releaseSubscription(_ subscriptionId: String?, legacy: @escaping @Sendable () async -> Void) async {
        if let subscriptionId, !subscriptionId.isEmpty {
            await releaseOwnedSubscription(subscriptionId)
        } else {
            await legacy()
        }
    }
}
