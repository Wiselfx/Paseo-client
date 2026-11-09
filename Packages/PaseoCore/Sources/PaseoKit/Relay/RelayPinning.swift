import Foundation
import PaseoProtocol
import Synchronization

// What a relay host was last known to be. Spec: docs/research/11-relay-pairing.md §5 "Pinning",
// §8.2 "SavedHosts"; ticket docs/tickets/R17-relay-transport.md.
//
// Two stores, on purpose:
//   RelayPinStore     non-secret: serverId, the daemon's *public* key, the security floor.
//   RelaySecretStore  the daemon password, i.e. Keychain in the app.
// Neither writes key *material* to plain settings: the only key here is public, and the secret
// path is a protocol so the app's existing Keychain helper can back it.

/// A relay host as this device remembers it. Nothing here is a secret.
public struct RelayPinnedHost: Codable, Sendable, Equatable, Identifiable {
    /// `srv_…`: stable daemon identity, and the relay session id.
    public var serverID: String
    /// The daemon's static X25519 key, base64. What the pairing offer pins and the fingerprint
    /// shows; a *changed* key means a different daemon is answering at that identity.
    public var daemonPublicKeyB64: String
    /// Floor this host negotiated. Only `protected` exists, so a pin can never be weakened; the
    /// field is what makes "this host was verified protected" durable across launches.
    public var minimumSecurityMode: ConnectionOffer.Security
    public var relayEndpoint: String
    public var relayUseTLS: Bool
    public var lastConnectedAt: Date?

    public var id: String { serverID }

    public init(
        serverID: String, daemonPublicKeyB64: String,
        minimumSecurityMode: ConnectionOffer.Security = .protected,
        relayEndpoint: String, relayUseTLS: Bool, lastConnectedAt: Date? = nil
    ) {
        self.serverID = serverID
        self.daemonPublicKeyB64 = daemonPublicKeyB64
        self.minimumSecurityMode = minimumSecurityMode
        self.relayEndpoint = relayEndpoint
        self.relayUseTLS = relayUseTLS
        self.lastConnectedAt = lastConnectedAt
    }

    public init(offer: ConnectionOffer, lastConnectedAt: Date? = nil) {
        self.init(
            serverID: offer.serverID, daemonPublicKeyB64: offer.daemonPublicKeyB64,
            minimumSecurityMode: .protected, relayEndpoint: offer.relayEndpoint,
            relayUseTLS: offer.relayUseTLS, lastConnectedAt: lastConnectedAt)
    }
}

/// What recording a successful relay connection changed about a host's identity.
public enum RelayIdentityChange: Sendable, Equatable {
    /// Never seen before.
    case newHost
    /// Same serverId and same daemon key.
    case unchanged
    /// Same serverId, different daemon key: re-pairing, a restore, or an impostor. The UI must
    /// ask before replacing the pin (upstream's "This link changes how you connect to this host").
    case daemonKeyChanged(previousB64: String)
}

/// Non-secret persistence for relay pins. The app backs this with UserDefaults; tests use
/// `InMemoryRelayPinStore`.
public protocol RelayPinStore: Sendable {
    func pins() -> [RelayPinnedHost]
    func pin(serverID: String) -> RelayPinnedHost?
    func save(_ pin: RelayPinnedHost)
    func remove(serverID: String)
}

/// The daemon password for a relay host. The app backs this with the same Keychain account scheme
/// `SavedHosts` already uses; tests use `InMemoryRelaySecretStore`.
///
/// Deliberately tiny and string-only: a password is the only secret a relay link carries, and
/// nothing derived from the Noise handshake is ever persisted.
public protocol RelaySecretStore: Sendable {
    func password(serverID: String) -> String?
    /// An empty string removes the item, matching the app's Keychain helper.
    func savePassword(_ password: String, serverID: String)
}

// MARK: - Floor

/// The security floor, and its persistence.
///
/// A relay connection is always `protected`: the type system already forbids anything else
/// (`ConnectionOffer.Security` has one case). What this class adds is durability and the rule that
/// a stored floor is never lowered — `record` takes the stronger of what the offer asks for and
/// what the pin already says, so a later offer cannot weaken a host that was verified protected.
/// The floor is structural, not a mutable knob: there is deliberately nothing to lower it to.
public final class RelayHostPins: Sendable {
    private let store: any RelayPinStore

    public init(store: any RelayPinStore) {
        self.store = store
    }

    public func pin(serverID: String) -> RelayPinnedHost? {
        store.pin(serverID: serverID)
    }

    public func pins() -> [RelayPinnedHost] {
        store.pins()
    }

    /// The floor for a connection made from this offer: the pinned mode when one is stored,
    /// otherwise the offer's own minimum, otherwise `protected`. Never lower than any of them.
    public func minimumSecurityMode(for offer: ConnectionOffer) -> ConnectionOffer.Security {
        let pinned = store.pin(serverID: offer.serverID)?.minimumSecurityMode
        return Self.maximum(pinned ?? offer.minimumSecurityMode ?? .protected, .protected)
    }

    /// Records a completed relay connection. Returns what changed about the host's identity so the
    /// caller can ask before replacing a pin.
    @discardableResult
    public func record(_ offer: ConnectionOffer, at date: Date = Date()) -> RelayIdentityChange {
        let change: RelayIdentityChange
        if let existing = store.pin(serverID: offer.serverID) {
            change =
                existing.daemonPublicKeyB64 == offer.daemonPublicKeyB64
                ? .unchanged
                : .daemonKeyChanged(previousB64: existing.daemonPublicKeyB64)
        } else {
            change = .newHost
        }
        var updated = RelayPinnedHost(offer: offer, lastConnectedAt: date)
        if let existing = store.pin(serverID: offer.serverID) {
            updated.minimumSecurityMode = Self.maximum(
                updated.minimumSecurityMode, existing.minimumSecurityMode)
        }
        store.save(updated)
        return change
    }

    public func forget(serverID: String) {
        store.remove(serverID: serverID)
    }

    /// The stronger of two floors. Exhaustive over today's single case, so adding a weaker mode
    /// later cannot silently lower a stored pin.
    private static func maximum(
        _ lhs: ConnectionOffer.Security, _ rhs: ConnectionOffer.Security
    ) -> ConnectionOffer.Security {
        switch (lhs, rhs) {
        case (.protected, _), (_, .protected): return .protected
        }
    }
}

// MARK: - Endpoint from an offer

extension ConnectionOffer {
    /// The endpoint for this offer. The credential is the offer's password, or the one already in
    /// the secret store when the link was scanned without it (`relay://` links may omit it).
    public func makeEndpoint(
        secrets: any RelaySecretStore, pins: RelayHostPins
    ) throws -> DaemonEndpoint {
        let password = password ?? secrets.password(serverID: serverID)
        let credential = password.flatMap { $0.isEmpty ? nil : Credential.password($0) }
        return try DaemonEndpoint(
            url: relayWebSocketURL(), credential: credential,
            relay: DaemonEndpoint.RelayLink(
                offer: self, minimumSecurityMode: pins.minimumSecurityMode(for: self)))
    }
}

// MARK: - In-memory implementations

/// Test/preview implementation of `RelayPinStore`. Thread-safe, no persistence.
public final class InMemoryRelayPinStore: RelayPinStore, @unchecked Sendable {
    private let mutex = Mutex<[String: RelayPinnedHost]>([:])

    public init() {}

    public func pins() -> [RelayPinnedHost] {
        mutex.withLock { $0.values.sorted { $0.serverID < $1.serverID } }
    }

    public func pin(serverID: String) -> RelayPinnedHost? {
        mutex.withLock { $0[serverID] }
    }

    public func save(_ pin: RelayPinnedHost) {
        mutex.withLock { $0[pin.serverID] = pin }
    }

    public func remove(serverID: String) {
        mutex.withLock { _ = $0.removeValue(forKey: serverID) }
    }
}

/// Test implementation of `RelaySecretStore`. Stands in for the app's Keychain.
public final class InMemoryRelaySecretStore: RelaySecretStore, @unchecked Sendable {
    private let mutex = Mutex<[String: String]>([:])

    public init() {}

    public func password(serverID: String) -> String? {
        mutex.withLock { $0[serverID] }
    }

    public func savePassword(_ password: String, serverID: String) {
        mutex.withLock { store in
            if password.isEmpty {
                store.removeValue(forKey: serverID)
            } else {
                store[serverID] = password
            }
        }
    }
}
