import Foundation

// Source: messages.ts `WSHelloMessageSchema`, `WSHelloRejectedMessageSchema`, `server_info` status.

/// Wire protocol version this client speaks. The daemon negotiates down to min(client, daemon).
public let paseoProtocolVersion = 1

public enum Credential: Sendable, Hashable {
    /// Daemon password (`paseo daemon set-password`). What the phone uses over LAN/Tailscale.
    case password(String)
    /// `$PASEO_HOME/local-credential`. Only for tools running on the daemon's own machine.
    case localCredential(String)
}

/// Client capability names this client advertises. Only advertise behavior this client implements.
/// Source: packages/protocol/src/client-capabilities.ts `CLIENT_CAPS`.
public enum ClientCapabilities {
    public static let helloRejection = "hello_rejection"
    public static let terminalChunkedReplay = "terminal_chunked_replay"
    /// The daemon honors `agent.provider_subagents.list.request` and pushes update events only
    /// to clients advertising this capability.
    public static let providerSubagents = "providerSubagents"
    /// Every behavior this client actually implements. No `binary_chunking_v1` sends (we never
    /// chunk) and no `owned_subscriptions` (we detach through the legacy terminal unsubscribe).
    public static let implemented: [String: Bool] = [
        helloRejection: true,
        terminalChunkedReplay: true,
        providerSubagents: true,
    ]
}

/// First frame after the socket opens. Not session-wrapped.
public struct Hello: Encodable, Sendable {
    public var type = "hello"
    public var clientId: String
    public var clientType = "mobile"
    public var protocolVersion = paseoProtocolVersion
    public var appVersion: String?
    public var auth: Auth?
    /// Client capability flags. Only advertise behavior this client implements.
    public var capabilities: [String: Bool]

    public struct Auth: Encodable, Sendable {
        public var kind: String
        public var password: String?
        public var token: String?
    }

    public init(clientId: String, appVersion: String?, credential: Credential?, capabilities: [String: Bool] = ClientCapabilities.implemented) {
        self.clientId = clientId
        self.appVersion = appVersion
        self.capabilities = capabilities
        switch credential {
        case .password(let p): auth = Auth(kind: "password", password: p)
        case .localCredential(let t): auth = Auth(kind: "localCredential", token: t)
        case nil: auth = nil
        }
    }
}

/// Sent instead of `server_info` when the hello is refused (then the socket closes with 4401).
public struct HelloRejected: Decodable, Sendable, Error {
    /// `password_required`, `incorrect_password`, `incompatible_protocol`.
    public var reason: String
}

/// `{"type":"session","message":{"type":"status","payload":{"status":"server_info",…}}}`.
/// Arrives once after a successful hello. `features` gates optional capabilities: check it in one
/// place (the store) and expose a clean flag to features, never branch on it in views.
public struct ServerInfo: Decodable, Sendable, Hashable {
    public var serverId: String
    public var hostname: String?
    public var version: String?
    public var protocolVersion: Int?
    public var permissions: [String]?
    public var features: [String: JSONValue]?

    public func hasFeature(_ name: String) -> Bool { features?[name] == .bool(true) }
}
