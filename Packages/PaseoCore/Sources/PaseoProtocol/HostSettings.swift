import Foundation

// Host settings: the daemon's mutable config, provider enable switches, agent profiles,
// client presence heartbeats, push-token registration and the slash-command menu.
//
// Source: messages.ts `MutableDaemonConfigSchema`, `MutableDaemonConfigPatchSchema`,
// `GetDaemonConfigRequestMessageSchema`, `GetDaemonConfigResponseMessageSchema`,
// `SetDaemonConfigRequestMessageSchema`, `SetDaemonConfigResponseMessageSchema`,
// `DaemonConfigChangedStatusPayloadSchema`, `ClientHeartbeatMessageSchema`,
// `RegisterPushTokenMessageSchema`, `PushUnregisterRequestSchema`,
// `PushUnregisterResponseSchema`, `ListCommandsRequestSchema`, `ListCommandsResponseSchema`,
// `AgentProfileSchema`.

// MARK: - Profiles

// Source: packages/protocol/src/agent-profile.ts `AgentProfileSchema`

/// A named launch bundle: provider plus the agent-config values a client would otherwise set one
/// control at a time. Field names mirror `AgentSessionConfig`. Profiles carry no system prompt.
public struct AgentProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// A key into the client's icon registry, not a glyph.
    public var icon: String?
    /// An identity colour name shared with host badges.
    public var color: String?
    public var provider: String
    public var model: String?
    public var modeId: String?
    public var thinkingOptionId: String?
    public var featureValues: [String: JSONValue]?
    /// Free text surfaced to orchestrating agents by the `list_profiles` MCP tool.
    public var notes: String?

    public init(
        id: String, name: String, icon: String? = nil, color: String? = nil, provider: String,
        model: String? = nil, modeId: String? = nil, thinkingOptionId: String? = nil,
        featureValues: [String: JSONValue]? = nil, notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.provider = provider
        self.model = model
        self.modeId = modeId
        self.thinkingOptionId = thinkingOptionId
        self.featureValues = featureValues
        self.notes = notes
    }
}

// MARK: - Daemon config

// Source: messages.ts `MutableDaemonProviderModelSchema`, `MutableDaemonProviderConfigSchema`

/// One custom model entry under `config.providers[provider].additionalModels`.
public struct DaemonProviderModel: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
    public var isDefault: Bool?

    public init(id: String, label: String, description: String? = nil, isDefault: Bool? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.isDefault = isDefault
    }
}

/// One provider's mutable daemon config. `enabled` is the provider enable switch used by the
/// host settings screen; `additionalModels` are user-added custom models.
public struct DaemonProviderConfig: Decodable, Sendable, Hashable {
    public var enabled: Bool?
    public var additionalModels: [DaemonProviderModel]?
    /// Provider-specific Paseo tool policy; kept raw because its shape is provider-owned.
    public var paseoTools: JSONValue?

    private enum K: String, CodingKey { case enabled, additionalModels, paseoTools }

    public init(
        enabled: Bool? = nil, additionalModels: [DaemonProviderModel]? = nil,
        paseoTools: JSONValue? = nil
    ) {
        self.enabled = enabled
        self.additionalModels = additionalModels
        self.paseoTools = paseoTools
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        additionalModels = try? c.decodeIfPresent([DaemonProviderModel].self, forKey: .additionalModels)
        paseoTools = try? c.decodeIfPresent(JSONValue.self, forKey: .paseoTools)
    }
}

// Source: messages.ts `MutableDaemonConfigSchema`

/// The daemon's read model for host settings. Unknown top-level keys are ignored; every nested
/// value is decoded leniently so a newer daemon cannot make the whole config unreadable.
public struct DaemonConfig: Decodable, Sendable, Hashable {
    public struct MCP: Decodable, Sendable, Hashable {
        public var enabled: Bool?
        public var injectIntoAgents: Bool?
    }

    public struct Relay: Decodable, Sendable, Hashable {
        public var enabled: Bool
        public var requireProtectedSecurity: Bool?
    }

    public struct Usage: Decodable, Sendable, Hashable {
        public var enabled: Bool
    }

    public struct BrowserTools: Decodable, Sendable, Hashable {
        public var enabled: Bool
    }

    public struct StructuredGenerationProvider: Codable, Sendable, Hashable {
        public var provider: String
        public var model: String?
        public var thinkingOptionId: String?

        public init(provider: String, model: String? = nil, thinkingOptionId: String? = nil) {
            self.provider = provider
            self.model = model
            self.thinkingOptionId = thinkingOptionId
        }
    }

    public struct MetadataGeneration: Codable, Sendable, Hashable {
        public var providers: [StructuredGenerationProvider]

        public init(providers: [StructuredGenerationProvider] = []) {
            self.providers = providers
        }
    }

    public var relay: Relay?
    public var mcp: MCP?
    public var usage: Usage?
    public var browserTools: BrowserTools?
    public var providers: [String: DaemonProviderConfig]
    public var metadataGeneration: MetadataGeneration?
    public var autoArchiveAfterMerge: Bool
    public var enableTerminalAgentHooks: Bool
    public var idleRuntimeCleanup: Bool?
    public var resumeOnStartup: Bool?
    public var resumePrompt: String?
    public var appendSystemPrompt: String
    public var agentProfiles: [AgentProfile]?
    public var pluginsEnabled: Bool?
    /// Read-only through `set_daemon_config_request`, but useful for diagnostics.
    public var hostnames: JSONValue?
    public var cors: JSONValue?
    public var trustedProxies: JSONValue?
    public var git: JSONValue?
    public var app: JSONValue?
    /// Speech settings and other feature-specific config; shape is owned by the daemon.
    public var features: JSONValue?
    public var skills: JSONValue?
    public var plugins: JSONValue?
    public var envOverrides: [String: String]?

    private enum K: String, CodingKey {
        case relay, mcp, usage, browserTools, providers, metadataGeneration
        case autoArchiveAfterMerge, enableTerminalAgentHooks, idleRuntimeCleanup
        case resumeOnStartup, resumePrompt, appendSystemPrompt, agentProfiles, pluginsEnabled
        case hostnames, cors, trustedProxies, git, app, features, skills, plugins, envOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        relay = try? c.decodeIfPresent(Relay.self, forKey: .relay)
        mcp = try? c.decodeIfPresent(MCP.self, forKey: .mcp)
        usage = try? c.decodeIfPresent(Usage.self, forKey: .usage)
        browserTools = try? c.decodeIfPresent(BrowserTools.self, forKey: .browserTools)
        providers = (try? c.decodeIfPresent([String: DaemonProviderConfig].self, forKey: .providers)) ?? [:]
        metadataGeneration = try? c.decodeIfPresent(MetadataGeneration.self, forKey: .metadataGeneration)
        autoArchiveAfterMerge = try c.decodeIfPresent(Bool.self, forKey: .autoArchiveAfterMerge) ?? false
        enableTerminalAgentHooks = try c.decodeIfPresent(Bool.self, forKey: .enableTerminalAgentHooks) ?? false
        idleRuntimeCleanup = try? c.decodeIfPresent(Bool.self, forKey: .idleRuntimeCleanup)
        resumeOnStartup = try? c.decodeIfPresent(Bool.self, forKey: .resumeOnStartup)
        resumePrompt = try? c.decodeIfPresent(String.self, forKey: .resumePrompt)
        appendSystemPrompt = try c.decodeIfPresent(String.self, forKey: .appendSystemPrompt) ?? ""
        agentProfiles = try? c.decodeIfPresent([AgentProfile].self, forKey: .agentProfiles)
        pluginsEnabled = try? c.decodeIfPresent(Bool.self, forKey: .pluginsEnabled)
        hostnames = try? c.decodeIfPresent(JSONValue.self, forKey: .hostnames)
        cors = try? c.decodeIfPresent(JSONValue.self, forKey: .cors)
        trustedProxies = try? c.decodeIfPresent(JSONValue.self, forKey: .trustedProxies)
        git = try? c.decodeIfPresent(JSONValue.self, forKey: .git)
        app = try? c.decodeIfPresent(JSONValue.self, forKey: .app)
        features = try? c.decodeIfPresent(JSONValue.self, forKey: .features)
        skills = try? c.decodeIfPresent(JSONValue.self, forKey: .skills)
        plugins = try? c.decodeIfPresent(JSONValue.self, forKey: .plugins)
        envOverrides = try? c.decodeIfPresent([String: String].self, forKey: .envOverrides)
    }
}

// Source: messages.ts `MutableDaemonConfigPatchSchema`

/// The patchable subset this client writes. Fields left nil stay out of the frame; `providers`
/// is a per-provider merge (`removeProviders` deletes entries). The daemon's patch schema is
/// narrower than its read model: hostnames, cors, trustedProxies, git, app, skills and
/// envOverrides are read-only through this RPC.
public struct DaemonConfigPatch: Encodable, Sendable, Equatable {
    public struct Relay: Encodable, Sendable, Equatable {
        public var enabled: Bool?
        public var requireProtectedSecurity: Bool?

        public init(enabled: Bool? = nil, requireProtectedSecurity: Bool? = nil) {
            self.enabled = enabled
            self.requireProtectedSecurity = requireProtectedSecurity
        }
    }

    public struct MCP: Encodable, Sendable, Equatable {
        public var injectIntoAgents: Bool?

        public init(injectIntoAgents: Bool? = nil) {
            self.injectIntoAgents = injectIntoAgents
        }
    }

    public struct Usage: Encodable, Sendable, Equatable {
        public var enabled: Bool?

        public init(enabled: Bool? = nil) {
            self.enabled = enabled
        }
    }

    public struct BrowserTools: Encodable, Sendable, Equatable {
        public var enabled: Bool?

        public init(enabled: Bool? = nil) {
            self.enabled = enabled
        }
    }

    public struct Provider: Encodable, Sendable, Equatable {
        public var enabled: Bool?
        public var additionalModels: [DaemonProviderModel]?
        public var paseoTools: JSONValue?

        public init(
            enabled: Bool? = nil, additionalModels: [DaemonProviderModel]? = nil,
            paseoTools: JSONValue? = nil
        ) {
            self.enabled = enabled
            self.additionalModels = additionalModels
            self.paseoTools = paseoTools
        }
    }

    public struct MetadataGeneration: Encodable, Sendable, Equatable {
        public var providers: [DaemonConfig.StructuredGenerationProvider]?

        public init(providers: [DaemonConfig.StructuredGenerationProvider]? = nil) {
            self.providers = providers
        }
    }

    public var relay: Relay?
    public var mcp: MCP?
    public var usage: Usage?
    public var browserTools: BrowserTools?
    public var providers: [String: Provider]?
    public var removeProviders: [String]?
    public var metadataGeneration: MetadataGeneration?
    public var autoArchiveAfterMerge: Bool?
    public var enableTerminalAgentHooks: Bool?
    public var idleRuntimeCleanup: Bool?
    public var resumeOnStartup: Bool?
    public var resumePrompt: String?
    public var appendSystemPrompt: String?
    public var agentProfiles: [AgentProfile]?
    public var pluginsEnabled: Bool?

    public init() {}
}

// Source: messages.ts `GetDaemonConfigRequestMessageSchema`,
// `GetDaemonConfigResponseMessageSchema`

public struct GetDaemonConfigRequest: PaseoRequest {
    public static let type = "get_daemon_config_request"
    public static let responseType = "get_daemon_config_response"
    public var requestId = ""
    public init() {}

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var config: DaemonConfig
    }
}

// Source: messages.ts `SetDaemonConfigRequestMessageSchema`,
// `SetDaemonConfigResponseMessageSchema`

public struct SetDaemonConfigRequest: PaseoRequest {
    public static let type = "set_daemon_config_request"
    public static let responseType = "set_daemon_config_response"
    public var requestId = ""
    public var config: DaemonConfigPatch
    public init(config: DaemonConfigPatch) { self.config = config }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var config: DaemonConfig
    }
}

// Source: messages.ts `DaemonConfigChangedStatusPayloadSchema`

/// `status` with `payload.status == "daemon_config_changed"`, carrying the full effective config.
public struct DaemonConfigChanged: Decodable, Sendable {
    public var status: String
    public var config: DaemonConfig
}

// MARK: - Presence

// Source: messages.ts `ClientHeartbeatMessageSchema`

public enum PresenceDeviceType: String, Sendable, Equatable {
    case web
    case mobile
}

/// Fire-and-forget presence. The daemon uses it to decide whether attention becomes push,
/// in-app notification, or nothing at all. There is no response.
public struct ClientHeartbeat: PaseoOutboundMessage {
    public static let type = "client_heartbeat"
    public var deviceType: PresenceDeviceType
    /// The agent the user is looking at, if any. Encoded as `null` when absent.
    public var focusedAgentId: String?
    /// COMPAT `terminalFocusHeartbeat`; encoded as `null` when absent.
    public var focusedTerminalId: String?
    public var lastActivityAt: String
    public var appVisible: Bool
    public var appVisibilityChangedAt: String?

    public init(
        deviceType: PresenceDeviceType = .mobile, focusedAgentId: String? = nil,
        focusedTerminalId: String? = nil, lastActivityAt: String, appVisible: Bool,
        appVisibilityChangedAt: String? = nil
    ) {
        self.deviceType = deviceType
        self.focusedAgentId = focusedAgentId
        self.focusedTerminalId = focusedTerminalId
        self.lastActivityAt = lastActivityAt
        self.appVisible = appVisible
        self.appVisibilityChangedAt = appVisibilityChangedAt
    }

    private enum K: String, CodingKey {
        case deviceType, focusedAgentId, focusedTerminalId, lastActivityAt, appVisible
        case appVisibilityChangedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(deviceType.rawValue, forKey: .deviceType)
        // The schema requires the nullable keys to be present; the daemon treats null as absent.
        if let focusedAgentId {
            try c.encode(focusedAgentId, forKey: .focusedAgentId)
        } else {
            try c.encodeNil(forKey: .focusedAgentId)
        }
        if let focusedTerminalId {
            try c.encode(focusedTerminalId, forKey: .focusedTerminalId)
        } else {
            try c.encodeNil(forKey: .focusedTerminalId)
        }
        try c.encode(lastActivityAt, forKey: .lastActivityAt)
        try c.encode(appVisible, forKey: .appVisible)
        if let appVisibilityChangedAt {
            try c.encode(appVisibilityChangedAt, forKey: .appVisibilityChangedAt)
        }
    }
}

// MARK: - Push registration

// Source: messages.ts `RegisterPushTokenMessageSchema`

/// Registers an Expo push token for this app install. Fire-and-forget; the daemon renews its
/// lease on each heartbeat.
public struct RegisterPushToken: PaseoOutboundMessage {
    public static let type = "register_push_token"
    public var token: String
    public init(token: String) { self.token = token }
}

// Source: messages.ts `PushUnregisterRequestSchema`, `PushUnregisterResponseSchema`

/// Revokes a push token. Gated for the sender on `features.pushTokenRevocation`.
public struct PushUnregisterRequest: PaseoRequest {
    public static let type = "push.unregister.request"
    public static let responseType = "push.unregister.response"
    public var requestId = ""
    public var token: String
    public init(token: String) { self.token = token }

    public struct Response: Decodable, Sendable {
        public var requestId: String
    }
}

// MARK: - Slash commands

// Source: messages.ts `ListCommandsDraftConfigSchema`

/// The draft config for listing commands before an agent exists. A draft needs an explicit model;
/// the daemon never resolves a default model for catalogue discovery.
public struct AgentDraftConfig: Encodable, Sendable, Hashable {
    public var provider: String
    public var cwd: String
    public var modeId: String?
    public var model: String?
    public var thinkingOptionId: String?
    public var featureValues: [String: JSONValue]?

    public init(
        provider: String, cwd: String, modeId: String? = nil, model: String? = nil,
        thinkingOptionId: String? = nil, featureValues: [String: JSONValue]? = nil
    ) {
        self.provider = provider
        self.cwd = cwd
        self.modeId = modeId
        self.model = model
        self.thinkingOptionId = thinkingOptionId
        self.featureValues = featureValues
    }
}

// Source: messages.ts `AgentSlashCommandSchema`

/// One provider-native or Paseo-injected slash command. `kind` is provider-defined; unknown values
/// stay usable rather than failing the whole response.
public enum AgentCommandKind: Sendable, Hashable {
    case command
    case skill
    case unknown(String)

    public init(wire: String?) {
        switch wire {
        case "command": self = .command
        case "skill": self = .skill
        case let other?: self = .unknown(other)
        case nil: self = .command
        }
    }
}

public struct AgentSlashCommand: Decodable, Sendable, Hashable, Identifiable {
    public var name: String
    public var description: String
    public var argumentHint: String
    public var kind: AgentCommandKind

    public nonisolated var id: String { name }

    private enum K: String, CodingKey { case name, description, argumentHint, kind }

    public init(name: String, description: String = "", argumentHint: String = "", kind: AgentCommandKind = .command) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        argumentHint = try c.decodeIfPresent(String.self, forKey: .argumentHint) ?? ""
        kind = AgentCommandKind(wire: try c.decodeIfPresent(String.self, forKey: .kind))
    }
}

// Source: messages.ts `ListCommandsRequestSchema`, `ListCommandsResponseSchema`

/// Lists slash commands for a live agent, or for a draft when `draftConfig` is present.
public struct ListCommandsRequest: PaseoRequest {
    public static let type = "list_commands_request"
    public static let responseType = "list_commands_response"
    public var requestId = ""
    public var agentId: String
    public var draftConfig: AgentDraftConfig?

    public init(agentId: String, draftConfig: AgentDraftConfig? = nil) {
        self.agentId = agentId
        self.draftConfig = draftConfig
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        public var commands: [AgentSlashCommand]
        public var error: String?

        private enum K: String, CodingKey { case requestId, agentId, commands, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            // Present in the source schema, but tolerate an older/partial daemon.
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? ""
            commands = (try? c.decodeIfPresent([AgentSlashCommand].self, forKey: .commands)) ?? []
            error = try? c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}
