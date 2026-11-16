import Foundation

// One daemon this device remembers. Non-secret only — the daemon password lives in the
// Keychain, one account per host id (see the app's SavedHosts / RelaySecretStore adapter).
//
// Identity: a relay host is keyed on `serverID` (+ the daemon public key), never on the URL —
// re-pairing the same daemon must find the same host and its password (R17 item 2). A direct
// host keeps its credential-free `ws(s)://…/ws` URL as the identity, but learns the daemon's
// `serverId` from `server_info` on the first successful connect (`directServerID`, M20b) so
// deep links can find it before it is the live host.
//
// Migration: hosts saved before relay pairing decode with nil relay fields; hosts saved before
// M20b decode with nil `directServerID`. id, label, URL and password (Keychain, untouched) all
// survive — see the migration tests.

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
    /// Direct only: the daemon's `serverId` from `server_info`, learned on a successful
    /// connect (M20b). Nil until the first connect; relay hosts leave it nil because
    /// `serverID` already carries the same identity.
    public var directServerID: String?
    /// Relay only: the daemon's static X25519 key, base64 (public — the trust anchor).
    public var daemonPublicKeyB64: String?
    /// Relay only: relay `host:port`.
    public var relayEndpoint: String?
    public var relayUseTLS: Bool?
    /// Relay only: the alternate direct endpoint (`ws(s)://host:port/ws`) this daemon was also
    /// added with on the same device. TLS is carried by the scheme. Nil until a direct row for
    /// the same daemon is merged in (`SavedHostMerge`).
    public var directURL: String? = nil

    public init(
        id: UUID = UUID(), label: String, url: String, lastConnectedAt: Date? = nil,
        serverID: String? = nil, daemonPublicKeyB64: String? = nil,
        relayEndpoint: String? = nil, relayUseTLS: Bool? = nil,
        directServerID: String? = nil
    ) {
        self.id = id
        self.label = label
        self.url = url
        self.lastConnectedAt = lastConnectedAt
        self.serverID = serverID
        self.daemonPublicKeyB64 = daemonPublicKeyB64
        self.relayEndpoint = relayEndpoint
        self.relayUseTLS = relayUseTLS
        self.directServerID = directServerID
    }

    public var isRelay: Bool { serverID != nil }

    /// The dedupe identity: relay hosts collapse onto their daemon identity, direct hosts
    /// onto their endpoint URL. A known `directServerID` does not join this key: a direct row
    /// folds into the relay row of the same daemon by `SavedHostMerge` (L2), not by key.
    public var identityKey: String { serverID.map { "relay:\($0)" } ?? url }

    /// The daemon's `serverId` when this row knows it, for relay and direct hosts alike.
    public var daemonServerID: String? { serverID ?? directServerID }

    /// Whether two saved rows name the same daemon. Detection only — see `identityKey`.
    public func isSameDaemon(as other: SavedHost) -> Bool {
        guard let mine = daemonServerID, let theirs = other.daemonServerID else { return false }
        return mine == theirs
    }

    /// Records the `serverId` learned from a live `server_info` (M20b). A different id is
    /// reported rather than silently dropped; the caller decides what to do with it.
    @discardableResult
    public mutating func learnDirectServerID(_ daemonServerID: String?) -> SavedHostServerIDChange {
        // A relay row already carries the same identity in `serverID`.
        guard self.serverID == nil, let daemonServerID else { return .unchanged }
        let trimmed = daemonServerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }
        guard let existing = directServerID else {
            directServerID = trimmed
            return .learned(trimmed)
        }
        guard existing != trimmed else { return .unchanged }
        directServerID = trimmed
        return .replaced(previous: existing, current: trimmed)
    }

    /// The connections this row can be reached through, with upstream's connection ids
    /// (packages/app/src/types/host-connection.ts:430-435, :441-453). A relay row has its relay
    /// route and, once merged, its direct route; a direct row has only its direct route.
    /// Computed, never stored.
    public var connections: [SavedHostConnection] {
        var out: [SavedHostConnection] = []
        if isRelay, let relayEndpoint = relayEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
            !relayEndpoint.isEmpty
        {
            // Upstream: `relay:wss:<endpoint>` when TLS is on, else `relay:<endpoint>`.
            let id = relayUseTLS == true ? "relay:wss:\(relayEndpoint)" : "relay:\(relayEndpoint)"
            out.append(SavedHostConnection(id: id, kind: .relay, endpoint: relayEndpoint))
        }
        if let directEndpoint = SavedHost.directEndpoint(isRelay ? directURL : url) {
            out.append(
                SavedHostConnection(
                    id: "direct:\(directEndpoint)", kind: .direct, endpoint: directEndpoint))
        }
        return out
    }

    /// The upstream `host:port` of a direct `ws(s)` URL, loopback folded to `localhost` as upstream
    /// does for stored direct connections (host-connection.ts:537). Nil when the URL names no
    /// host or no explicit port (upstream `normalizeHostPort` requires one).
    static func directEndpoint(_ urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString),
            let rawHost = url.host, !rawHost.isEmpty, let port = url.port
        else { return nil }
        let bareHost = rawHost.hasPrefix("[") && rawHost.hasSuffix("]")
            ? String(rawHost.dropFirst().dropLast()) : rawHost
        if bareHost == "127.0.0.1" || bareHost == "0.0.0.0" || bareHost == "::1" || bareHost == "::" {
            return "localhost:\(port)"
        }
        return bareHost.contains(":") ? "[\(bareHost)]:\(port)" : "\(bareHost):\(port)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, url, lastConnectedAt, serverID, daemonPublicKeyB64, relayEndpoint
        case relayUseTLS, directServerID, directURL
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
        directServerID = try c.decodeIfPresent(String.self, forKey: .directServerID)
        directURL = try c.decodeIfPresent(String.self, forKey: .directURL)
    }
}

/// One way to reach a saved host. `id` is upstream's connection id; `endpoint` is the relay
/// endpoint (relay) or the normalized `host:port` (direct).
public struct SavedHostConnection: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case relay
        case direct
    }

    public let id: String
    public let kind: Kind
    public let endpoint: String

    public init(id: String, kind: Kind, endpoint: String) {
        self.id = id
        self.kind = kind
        self.endpoint = endpoint
    }
}

/// What learning a direct host's daemon identity did (M20b).
public enum SavedHostServerIDChange: Sendable, Equatable {
    /// First identity seen for this row.
    case learned(String)
    /// Same id as before, or nothing to learn.
    case unchanged
    /// The daemon reported a different id than the one stored. The new id is stored; the
    /// caller is told rather than left with a silent overwrite.
    case replaced(previous: String, current: String)
}

/// Saved rows that name the same daemon more than once — usually a direct row and a relay
/// row for one machine. Detection here; `mergePlan` (SavedHostMerge.swift) says which pairs fold.
public enum SavedHostDuplicates {
    /// Groups of two or more rows sharing a daemon id, ordered by id; input order inside a
    /// group. Rows with no known daemon id are never grouped.
    public static func groups(_ hosts: [SavedHost]) -> [[SavedHost]] {
        var byServerID: [String: [SavedHost]] = [:]
        for host in hosts {
            guard let serverID = host.daemonServerID else { continue }
            byServerID[serverID, default: []].append(host)
        }
        return byServerID.keys.sorted().compactMap { key in
            guard let group = byServerID[key], group.count > 1 else { return nil }
            return group
        }
    }

    /// The daemon ids with more than one saved row.
    public static func serverIDs(_ hosts: [SavedHost]) -> [String] {
        groups(hosts).compactMap { $0.first?.daemonServerID }
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
