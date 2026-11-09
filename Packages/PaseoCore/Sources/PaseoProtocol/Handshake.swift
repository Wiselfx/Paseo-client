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
    /// to clients advertising this capability. The wire name is snake_case, like every other
    /// entry in `CLIENT_CAPS` (`packages/protocol/src/client-capabilities.ts`: `providerSubagents:
    /// "provider_subagents"`); a camelCase key is silently ignored by the daemon, so the
    /// subagent list never refreshed and the chat pill never appeared.
    public static let providerSubagents = "provider_subagents"
    /// Every behavior this client actually implements. No `binary_chunking_v1` sends (we never
    /// chunk). `owned_subscriptions` and its `workspace_setup_observation` companion are
    /// advertised only while `OwnedSubscriptions.isEnabled`; every subscription path in the
    /// stores implements the modern protocol (see `docs/research/09-owned-subscriptions.md`).
    /// `voice` is advertised only while `VoiceMode.isEnabled` (realtime voice mode,
    /// `VoiceModeSession`).
    public static let implemented: [String: Bool] = {
        var capabilities: [String: Bool] = [
            helloRejection: true,
            terminalChunkedReplay: true,
            providerSubagents: true,
        ]
        if OwnedSubscriptions.isEnabled {
            capabilities[OwnedSubscriptions.capability] = true
            capabilities[OwnedSubscriptions.setupObservationCapability] = true
        }
        if VoiceMode.isEnabled {
            capabilities[VoiceMode.capability] = true
        }
        return capabilities
    }()
}

/// Oldest app version the daemon treats as provider-aware. Before it (see `MIN_VERSION_ALL_PROVIDERS`
/// in `packages/server/src/server/session.ts`) the daemon hides every provider outside the legacy
/// `claude`/`codex`/`opencode` set, because those clients validate provider ids against a closed
/// enum and reject a whole session message that names `pi`, `omp`, etc. This client decodes
/// provider ids as strings, so it can honestly advertise this floor. Source: `messages.ts`
/// `WSHelloMessageSchema` and `docs/providers.md`.
public let paseoProviderAwareAppVersion = "0.1.45"

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
        self.appVersion = Self.wireAppVersion(appVersion)
        self.capabilities = capabilities
        switch credential {
        case .password(let p): auth = Auth(kind: "password", password: p)
        case .localCredential(let t): auth = Auth(kind: "localCredential", token: t)
        case nil: auth = nil
        }
    }

    /// The daemon's provider list is gated on the app version we advertise (see
    /// `paseoProviderAwareAppVersion`). The marketing version in the bundle can be lower than that
    /// gate — an early app build is not an old client — so the hello never claims less than the
    /// protocol behavior this client actually has. Versions at or above the floor pass through.
    private static func wireAppVersion(_ appVersion: String?) -> String {
        guard let appVersion, isAtLeast(appVersion, paseoProviderAwareAppVersion) else {
            return paseoProviderAwareAppVersion
        }
        return appVersion
    }

    /// Numeric dotted-version comparison, ignoring prerelease suffixes, same rule as the daemon.
    private static func isAtLeast(_ version: String, _ minimum: String) -> Bool {
        let base = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let parts = base.split(separator: ".").map { Int($0) ?? 0 }
        let minimumParts = minimum.split(separator: ".").map { Int($0) ?? 0 }
        for index in minimumParts.indices {
            let value = index < parts.count ? parts[index] : 0
            let required = minimumParts[index]
            if value > required { return true }
            if value < required { return false }
        }
        return true
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
    /// Daemon readiness per capability (`capabilities.voice`, absent on old daemons).
    public var capabilities: ServerCapabilities?

    public func hasFeature(_ name: String) -> Bool { features?[name] == .bool(true) }

    /// Realtime voice readiness, when the daemon reports it (`isUsable` mirrors
    /// `resolveVoiceUnavailableMessage` returning nil).
    public var voiceReadiness: ServerCapabilityState? { capabilities?.voice?.voice }

    /// Whether this daemon says realtime voice mode is usable right now.
    public var isVoiceAvailable: Bool { voiceReadiness?.isUsable == true }
}
