import Foundation

// One daemon this device remembers. Non-secret only — the daemon password lives in the
// Keychain, one account per host id (see the app's SavedHosts / RelaySecretStore adapter).
//
// Identity: a relay host is keyed on `serverID` (+ the daemon public key), never on the URL —
// re-pairing the same daemon must find the same host and its password (R17 item 2). A direct
// host keeps its credential-free `ws(s)://…/ws` URL as the identity.
//
// Migration: hosts saved before relay pairing decode with nil relay fields; id, label, URL
// and password (Keychain, untouched) all survive — see `relayFields` and the migration test.

public struct SavedHost: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// User-editable label; defaults to the host part of the URL (direct) or the server id.
    public var label: String
    /// Direct connections: full `ws(s)://host:port/ws`, credential-free. Relay hosts keep
    /// the relay WebSocket URL here for display; identity comes from `serverID`.
    public var url: String
    public var lastConnectedAt: Date?
    /// Relay only: `srv_…` daemon identity and relay session id.
    public var serverID: String?
    /// Relay only: the daemon's static X25519 key, base64 (public — the trust anchor).
    public var daemonPublicKeyB64: String?
    /// Relay only: relay `host:port`.
    public var relayEndpoint: String?
    public var relayUseTLS: Bool?

    public init(
        id: UUID = UUID(), label: String, url: String, lastConnectedAt: Date? = nil,
        serverID: String? = nil, daemonPublicKeyB64: String? = nil,
        relayEndpoint: String? = nil, relayUseTLS: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.lastConnectedAt = lastConnectedAt
        self.serverID = serverID
        self.daemonPublicKeyB64 = daemonPublicKeyB64
        self.relayEndpoint = relayEndpoint
        self.relayUseTLS = relayUseTLS
    }

    public var isRelay: Bool { serverID != nil }

    /// The dedupe identity: relay hosts collapse onto their daemon identity, direct hosts
    /// onto their endpoint URL.
    public var identityKey: String { serverID.map { "relay:\($0)" } ?? url }

    private enum CodingKeys: String, CodingKey {
        case id, label, url, lastConnectedAt, serverID, daemonPublicKeyB64, relayEndpoint
        case relayUseTLS
    }

    /// Tolerant: pre-relay blobs (no relay keys at all) decode with nil relay fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        url = try c.decode(String.self, forKey: .url)
        lastConnectedAt = try c.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        serverID = try c.decodeIfPresent(String.self, forKey: .serverID)
        daemonPublicKeyB64 = try c.decodeIfPresent(String.self, forKey: .daemonPublicKeyB64)
        relayEndpoint = try c.decodeIfPresent(String.self, forKey: .relayEndpoint)
        relayUseTLS = try c.decodeIfPresent(Bool.self, forKey: .relayUseTLS)
    }
}

// MARK: - Host confirmation (upstream runtime/host-confirmation.ts)

/// Whether a pairing link asks anything at all, and which body it shows. Upstream asks
/// before a new host or a changed key/relay/TLS setting; an exact match asks nothing.
public enum HostConfirmationKind: Sendable, Equatable {
    case newHost
    case changedConnection
}

public enum HostConfirmation {
    /// The confirmation for this offer against the saved hosts, or nil when the link
    /// matches a saved host exactly (upstream `confirmLink` → resolve true without asking).
    public static func confirmationKind(
        offer: ConnectionOffer, savedHosts: [SavedHost]
    ) -> HostConfirmationKind? {
        guard let saved = savedHosts.first(where: { $0.serverID == offer.serverID }) else {
            return .newHost
        }
        let exact =
            saved.daemonPublicKeyB64 == offer.daemonPublicKeyB64
            && saved.relayEndpoint == offer.relayEndpoint
            && saved.relayUseTLS == offer.relayUseTLS
        return exact ? nil : .changedConnection
    }

    /// Upstream `formatDaemonKeyFingerprint` verbatim: strip non-alphanumerics from the key
    /// *string itself* (not a hash), groups of four; longer than 16 chars shows the first
    /// and last eight. The user compares this against what the daemon shows.
    public static func keyFingerprint(_ daemonPublicKeyB64: String) -> String {
        let normalized = daemonPublicKeyB64.filter { $0.isLetter || $0.isNumber }
        func group(_ slice: String) -> String {
            var out = ""
            var index = slice.startIndex
            while index < slice.endIndex {
                let next = slice.index(index, offsetBy: 4, limitedBy: slice.endIndex) ?? slice.endIndex
                if !out.isEmpty { out += " " }
                out += slice[index..<next]
                index = next
            }
            return out
        }
        if normalized.count <= 16 { return group(normalized) }
        return "\(group(String(normalized.prefix(8)))) … \(group(String(normalized.suffix(8))))"
    }
}
