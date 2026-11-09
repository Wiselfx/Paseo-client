import Foundation

// The pairing offer: the trust anchor for a relay connection.
// Spec: docs/research/11-relay-pairing.md §3; upstream `packages/protocol/src/connection-offer.ts`
// and `packages/protocol/src/daemon-endpoints.ts`.
//
// Two link shapes carry the same payload:
//   <app base url>/#offer=<base64url(json)>        what the QR code and "copy link" produce
//   relay://<endpoint>/<serverId>?key=<b64>&...    the CLI/legacy shape, also inside #connect=
//
// The daemon's static X25519 key rides in the fragment, so the web host never sees it. Treat the
// whole link like a password: whoever holds it can reach a daemon with no password set.

/// Everything a link can be refused for. Messages never echo the link, which is a credential.
public enum ConnectionOfferError: Error, Equatable, Sendable {
    case missingOfferFragment
    case emptyOfferPayload
    case invalidBase64
    case malformedOffer
    case unsupportedVersion(Int)
    case missingServerID
    case invalidServerID
    case invalidDaemonPublicKey
    case invalidRelayEndpoint
    case unsupportedSecurityMode(String)
    case unsupportedRelayURI
}

/// A validated relay pairing offer. Constructing one means every field has been checked, so the
/// rest of the client never re-parses key material.
public struct ConnectionOffer: Sendable, Equatable {
    /// The only endpoint security this client accepts on a relay connection.
    public enum Security: String, Sendable, Equatable {
        case protected
    }

    public static let offerFragmentPrefix = "#offer="
    public static let connectFragmentPrefix = "#connect="
    public static let relayURIScheme = "relay://"
    public static let protocolVersion = 2
    /// `useTls` defaults to on for the hosted relay's port when the offer omits it.
    public static let defaultTLSPort = 443
    public static let relayProtocolVersion = "2"
    public static let keyByteCount = 32

    /// Stable daemon identity; also the relay session id.
    public var serverID: String
    public var daemonPublicKeyB64: String
    /// Decoded 32-byte X25519 public key. `relay://` offers carry it, and every offer needs it.
    public var daemonPublicKey: [UInt8]
    /// `host:port`, normalized, exactly as it must go into the relay URL.
    public var relayEndpoint: String
    public var relayUseTLS: Bool
    /// Present only when the daemon demands protected endpoint security from the first handshake.
    public var minimumSecurityMode: Security?
    /// Only `relay://` links carry the daemon password.
    public var password: String?

    /// Set when the offer pins protected mode, so a legacy handshake must be refused (close 4002).
    public var requiresProtectedSecurity: Bool { minimumSecurityMode == .protected }

    public init(
        serverID: String, daemonPublicKeyB64: String, daemonPublicKey: [UInt8],
        relayEndpoint: String, relayUseTLS: Bool, minimumSecurityMode: Security? = nil,
        password: String? = nil
    ) {
        self.serverID = serverID
        self.daemonPublicKeyB64 = daemonPublicKeyB64
        self.daemonPublicKey = daemonPublicKey
        self.relayEndpoint = relayEndpoint
        self.relayUseTLS = relayUseTLS
        self.minimumSecurityMode = minimumSecurityMode
        self.password = password
    }

    // MARK: Parsing

    /// Parses a QR payload, a pasted link or a `relay://` URI. Throws `ConnectionOfferError`.
    public init(link: String) throws {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: Self.connectFragmentPrefix) {
            try self.init(relayURI: Self.percentDecode(String(trimmed[range.upperBound...]), plusIsSpace: false))
            return
        }
        if trimmed.hasPrefix(Self.relayURIScheme) {
            try self.init(relayURI: trimmed)
            return
        }
        guard let range = trimmed.range(of: Self.offerFragmentPrefix) else {
            throw ConnectionOfferError.missingOfferFragment
        }
        let encoded = String(trimmed[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encoded.isEmpty else { throw ConnectionOfferError.emptyOfferPayload }
        guard let payload = Self.decodeBase64URL(encoded) else {
            throw ConnectionOfferError.invalidBase64
        }
        try self.init(json: payload)
    }

    /// Parses the decoded offer JSON. Unknown fields are ignored, as upstream's schema does.
    public init(json payload: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: payload),
            let fields = object as? [String: Any]
        else { throw ConnectionOfferError.malformedOffer }

        guard let version = fields["v"] as? Int else {
            throw ConnectionOfferError.malformedOffer
        }
        guard version == Self.protocolVersion else {
            throw ConnectionOfferError.unsupportedVersion(version)
        }
        guard let serverID = fields["serverId"] as? String, !serverID.isEmpty else {
            throw ConnectionOfferError.missingServerID
        }
        guard let keyB64 = fields["daemonPublicKeyB64"] as? String else {
            throw ConnectionOfferError.invalidDaemonPublicKey
        }
        let key = try Self.decodePublicKey(keyB64)
        guard let relay = fields["relay"] as? [String: Any],
            let endpoint = relay["endpoint"] as? String
        else { throw ConnectionOfferError.malformedOffer }
        let normalizedEndpoint = try Self.normalizeEndpoint(endpoint)
        let useTLS: Bool
        if let explicit = relay["useTls"] as? Bool {
            useTLS = explicit
        } else {
            useTLS = Self.port(of: normalizedEndpoint) == Self.defaultTLSPort
        }
        let security: Security?
        if let raw = fields["minimumSecurityMode"] {
            guard let rawString = raw as? String else {
                throw ConnectionOfferError.malformedOffer
            }
            guard let parsed = Security(rawValue: rawString) else {
                // A pin we do not understand must not be silently ignored: fail closed.
                throw ConnectionOfferError.unsupportedSecurityMode(rawString)
            }
            security = parsed
        } else {
            security = nil
        }

        self.init(
            serverID: serverID, daemonPublicKeyB64: keyB64, daemonPublicKey: key,
            relayEndpoint: normalizedEndpoint, relayUseTLS: useTLS, minimumSecurityMode: security)
    }

    /// Parses `relay://<endpoint>/<serverId>?key=<b64>&ssl=true&security=protected&password=…`.
    public init(relayURI uri: String) throws {
        guard uri.hasPrefix(Self.relayURIScheme) else {
            throw ConnectionOfferError.unsupportedRelayURI
        }
        let rest = uri.dropFirst(Self.relayURIScheme.count)
        guard let slash = rest.firstIndex(of: "/") else {
            throw ConnectionOfferError.unsupportedRelayURI
        }
        let authority = String(rest[rest.startIndex..<slash])
        // Userinfo has no meaning here and upstream's URL-based parser rejects it.
        guard !authority.contains("@") else { throw ConnectionOfferError.unsupportedRelayURI }
        let pathAndQuery = String(rest[rest.index(after: slash)...])
        let endpoint = try Self.normalizeEndpoint(authority)

        let path: String
        let queryItems: [String: String]
        if let question = pathAndQuery.firstIndex(of: "?") {
            path = String(pathAndQuery[pathAndQuery.startIndex..<question])
            queryItems = Self.parseQuery(String(pathAndQuery[pathAndQuery.index(after: question)...]))
        } else {
            path = pathAndQuery
            queryItems = [:]
        }
        let serverID = Self.percentDecode(path, plusIsSpace: false)
        guard !serverID.isEmpty else { throw ConnectionOfferError.missingServerID }
        guard !serverID.contains("/") else { throw ConnectionOfferError.invalidServerID }
        guard let keyB64 = queryItems["key"], !keyB64.isEmpty else {
            throw ConnectionOfferError.invalidDaemonPublicKey
        }
        let key = try Self.decodePublicKey(keyB64)

        let security: Security?
        if let raw = queryItems["security"] {
            guard let parsed = Security(rawValue: raw) else {
                throw ConnectionOfferError.unsupportedSecurityMode(raw)
            }
            security = parsed
        } else {
            security = nil
        }
        let useTLS = queryItems["ssl"] == "true"
        let password = queryItems["password"].flatMap { $0.isEmpty ? nil : $0 }

        self.init(
            serverID: serverID, daemonPublicKeyB64: keyB64, daemonPublicKey: key,
            relayEndpoint: endpoint, relayUseTLS: useTLS, minimumSecurityMode: security,
            password: password)
    }

    // MARK: Relay URL

    /// The client WebSocket URL. The relay assigns the per-connection routing id, so none is sent.
    public func relayWebSocketURL() throws -> URL {
        let scheme = relayUseTLS ? "wss" : "ws"
        let urlString =
            "\(scheme)://\(relayEndpoint)/ws"
            + "?serverId=\(Self.percentEncode(serverID))"
            + "&role=client"
            + "&v=\(Self.relayProtocolVersion)"
        guard let url = URL(string: urlString) else {
            throw ConnectionOfferError.invalidRelayEndpoint
        }
        return url
    }

    // MARK: Validation

    /// Upstream's `validatedEndpoint` grammar: `host:port`, or a bracketed IPv6 literal.
    static func normalizeEndpoint(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") {
            guard let close = trimmed.firstIndex(of: "]") else {
                throw ConnectionOfferError.invalidRelayEndpoint
            }
            let literal = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            let after = trimmed[trimmed.index(after: close)...]
            guard !literal.isEmpty, literal.allSatisfy(isIPv6Character) else {
                throw ConnectionOfferError.invalidRelayEndpoint
            }
            guard after.hasPrefix(":") else { throw ConnectionOfferError.invalidRelayEndpoint }
            let port = try validatedPort(Substring(after.dropFirst()))
            return "[\(literal)]:\(port)"
        }
        guard let colon = trimmed.lastIndex(of: ":") else {
            throw ConnectionOfferError.invalidRelayEndpoint
        }
        let host = trimmed[trimmed.startIndex..<colon]
        guard let first = host.first, isHostCharacter(first), first != "-", first != "." else {
            throw ConnectionOfferError.invalidRelayEndpoint
        }
        guard host.allSatisfy(isHostCharacter) else {
            throw ConnectionOfferError.invalidRelayEndpoint
        }
        let port = try validatedPort(Substring(trimmed[trimmed.index(after: colon)...]))
        return "\(host):\(port)"
    }

    private static func validatedPort(_ text: Substring) throws -> Int {
        guard !text.isEmpty, text.count <= 5,
            text.allSatisfy({ $0.isASCII && $0.isNumber })
        else { throw ConnectionOfferError.invalidRelayEndpoint }
        guard let port = Int(text), (1...65535).contains(port) else {
            throw ConnectionOfferError.invalidRelayEndpoint
        }
        return port
    }

    /// The port half of a normalized endpoint; always parses because `normalizeEndpoint` ran.
    static func port(of endpoint: String) -> Int? {
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        return Int(endpoint[endpoint.index(after: colon)...])
    }

    /// Strict standard base64, 32 bytes, canonical: the same rules the daemon's `importPublicKey`
    /// applies, so a key we accept is a key the daemon produced.
    static func decodePublicKey(_ encoded: String) throws -> [UInt8] {
        guard !encoded.isEmpty else { throw ConnectionOfferError.invalidDaemonPublicKey }
        let bytes = try decodeStandardBase64(encoded)
        guard bytes.count == Self.keyByteCount else {
            throw ConnectionOfferError.invalidDaemonPublicKey
        }
        return bytes
    }

    static func decodeStandardBase64(_ encoded: String) throws -> [UInt8] {
        guard !encoded.isEmpty, encoded.count % 4 == 0 else {
            throw ConnectionOfferError.invalidBase64
        }
        for (index, character) in encoded.enumerated() {
            let isPadding = character == "="
            let isAlphabet =
                character.isASCII
                && (character.isLetter || character.isNumber || character == "+" || character == "/")
            guard isAlphabet || isPadding else { throw ConnectionOfferError.invalidBase64 }
            if isPadding, index < encoded.count - 2 {
                throw ConnectionOfferError.invalidBase64
            }
        }
        guard let data = Data(base64Encoded: encoded) else {
            throw ConnectionOfferError.invalidBase64
        }
        // Re-encoding equality rejects non-canonical trailing bits.
        guard data.base64EncodedString() == encoded else {
            throw ConnectionOfferError.invalidBase64
        }
        return Array(data)
    }

    static func decodeBase64URL(_ encoded: String) -> Data? {
        var standard = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder == 1 { return nil }
        if remainder != 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: standard)
    }

    // MARK: Character and percent rules

    private static func isHostCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "-"
            || character == "."
    }

    private static func isIPv6Character(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isHexDigit || character == ":" || character == "."
    }

    private static func percentEncode(_ value: String) -> String {
        var out = ""
        for byte in Array(value.utf8) {
            let isUnreserved =
                (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x2E
                || byte == 0x5F || byte == 0x7E
            if isUnreserved {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// Percent-decoding that never throws away bytes: invalid escapes are kept literally.
    /// `plusIsSpace` mirrors `URLSearchParams`, which upstream uses for query values.
    static func percentDecode(_ value: String, plusIsSpace: Bool) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        let source = Array(value.utf8)
        var index = 0
        while index < source.count {
            let byte = source[index]
            if byte == 0x25, index + 2 < source.count,
                let high = hexValue(source[index + 1]), let low = hexValue(source[index + 2])
            {
                bytes.append(high << 4 | low)
                index += 3
                continue
            }
            if plusIsSpace, byte == 0x2B {
                bytes.append(0x20)
            } else {
                bytes.append(byte)
            }
            index += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }

    private static func parseQuery(_ query: String) -> [String: String] {
        var items: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = percentDecode(String(parts[0]), plusIsSpace: true)
            let value = parts.count > 1 ? percentDecode(String(parts[1]), plusIsSpace: true) : ""
            if items[name] == nil { items[name] = value }
        }
        return items
    }
}
