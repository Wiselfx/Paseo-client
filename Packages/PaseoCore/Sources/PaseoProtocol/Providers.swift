import Foundation

// Provider and model discovery for the new-agent pickers.
// Source: messages.ts `ProviderSnapshotEntrySchema`, `AgentModelDefinitionSchema`,
// `GetProvidersSnapshotRequestMessageSchema`, `GetProvidersSnapshotResponseMessageSchema`,
// `RefreshProvidersSnapshotRequestMessageSchema`, `RefreshProvidersSnapshotResponseMessageSchema`,
// `ListProviderModelsRequestMessageSchema`, `ListProviderModesRequestMessageSchema`,
// `ListAvailableProvidersRequestMessageSchema` and their responses.

// Source: messages.ts `ProviderStatusSchema`

public enum ProviderStatus: Sendable, Hashable {
    case ready, loading, error, unavailable
    case unknown(String)

    public init(wire: String?) {
        switch wire {
        case "ready": self = .ready
        case "loading": self = .loading
        case "error": self = .error
        case "unavailable": self = .unavailable
        case let other?: self = .unknown(other)
        case nil: self = .unknown("")
        }
    }
}

// Source: messages.ts `AgentSelectOptionSchema`

/// One choice in a provider's thinking-level menu.
public struct ProviderThinkingOption: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var label: String
    public var description: String?
    public var isDefault: Bool?
    public var metadata: JSONValue?
}

// Source: messages.ts `AgentModelDefinitionSchema`

/// `AgentModelDefinitionSchema`: one model a provider can run.
public struct AgentModelDefinition: Sendable, Hashable, Decodable, Identifiable {
    public var provider: String
    public var id: String
    public var label: String
    public var description: String?
    public var aliases: [String]?
    public var isSelectable: Bool?
    public var isDefault: Bool?
    public var contextWindowMaxTokens: Double?
    public var thinkingOptions: [ProviderThinkingOption]?
    public var defaultThinkingOptionId: String?
    public var metadata: JSONValue?
}

// Source: messages.ts `ProviderSnapshotEntrySchema`

/// `ProviderSnapshotEntrySchema`: one provider's availability and catalogue as of `fetchedAt`.
public struct ProviderSnapshotEntry: Sendable, Hashable, Decodable, Identifiable {
    public var provider: String
    public var status: ProviderStatus
    public var enabled: Bool
    /// `builtin` or `custom`; open set.
    public var source: String?
    public var error: String?
    public var models: [AgentModelDefinition]?
    public var modes: [AgentMode]?
    public var fetchedAt: String?
    public var label: String?
    public var description: String?
    public var iconSvg: String?
    public var defaultModeId: String?

    public var id: String { provider }

    /// Usable for a new agent: enabled and probed ready.
    public var isAvailable: Bool { enabled && status == .ready }

    public init(
        provider: String, status: ProviderStatus, enabled: Bool = true, source: String? = nil,
        error: String? = nil, models: [AgentModelDefinition]? = nil, modes: [AgentMode]? = nil,
        fetchedAt: String? = nil, label: String? = nil, description: String? = nil,
        iconSvg: String? = nil, defaultModeId: String? = nil
    ) {
        self.provider = provider
        self.status = status
        self.enabled = enabled
        self.source = source
        self.error = error
        self.models = models
        self.modes = modes
        self.fetchedAt = fetchedAt
        self.label = label
        self.description = description
        self.iconSvg = iconSvg
        self.defaultModeId = defaultModeId
    }

    private enum K: String, CodingKey {
        case provider, status, enabled, source, error, models, modes, fetchedAt, label, description
        case iconSvg, defaultModeId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        provider = try c.decode(String.self, forKey: .provider)
        status = ProviderStatus(wire: try c.decodeIfPresent(String.self, forKey: .status))
        // Defaults to true upstream; an absent flag must not hide a provider.
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        source = try c.decodeIfPresent(String.self, forKey: .source)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        models = try? c.decodeIfPresent([AgentModelDefinition].self, forKey: .models)
        modes = try? c.decodeIfPresent([AgentMode].self, forKey: .modes)
        fetchedAt = try c.decodeIfPresent(String.self, forKey: .fetchedAt)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        iconSvg = try c.decodeIfPresent(String.self, forKey: .iconSvg)
        defaultModeId = try c.decodeIfPresent(String.self, forKey: .defaultModeId)
    }
}

// Source: messages.ts `GetProvidersSnapshotRequestMessageSchema`,
// `GetProvidersSnapshotResponseMessageSchema`

/// The full catalogue in one correlated call. Requires `features.providersSnapshot`; older daemons
/// answer with an error and the store falls back to the per-provider list RPCs.
public struct GetProvidersSnapshotRequest: PaseoRequest {
    public static let type = "get_providers_snapshot_request"
    public static let responseType = "get_providers_snapshot_response"
    public var requestId = ""
    /// Target-specific catalogue; omit for the global scope.
    public var cwd: String?
    public init(cwd: String? = nil) { self.cwd = cwd }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var entries: [ProviderSnapshotEntry]
        public var notModified: Bool?
        public var snapshotHash: String?
        public var generatedAt: String?
    }
}

// Source: messages.ts `ProvidersSnapshotUpdateMessageSchema`

/// `providers_snapshot_update`: the daemon pushing a scope's catalogue after a provider finishes
/// probing. Unsolicited (no correlation id) and scoped by `cwd`; entries replace the ones we hold.
public struct ProvidersSnapshotUpdate: Decodable, Sendable {
    /// Scope of this catalogue. Absent for the global scope.
    public var cwd: String?
    /// Daemon-side watch subscription, when the client asked for explicit subscriptions.
    public var subscriptionId: String?
    public var generatedAt: String?
    public var entries: [ProviderSnapshotEntry]
}

// Source: messages.ts `RefreshProvidersSnapshotRequestMessageSchema`,
// `RefreshProvidersSnapshotResponseMessageSchema`

/// Forces re-discovery. Acknowledges immediately; the refreshed entries arrive by snapshot pull
/// or `providers_snapshot_update`.
public struct RefreshProvidersSnapshotRequest: PaseoRequest {
    public static let type = "refresh_providers_snapshot_request"
    public static let responseType = "refresh_providers_snapshot_response"
    public var requestId = ""
    public var cwd: String?
    public var providers: [String]?
    public init(cwd: String? = nil, providers: [String]? = nil) {
        self.cwd = cwd
        self.providers = providers
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var acknowledged: Bool
    }
}

// Source: messages.ts `ListProviderModelsRequestMessageSchema`

public struct ListProviderModelsRequest: PaseoRequest {
    public static let type = "list_provider_models_request"
    public static let responseType = "list_provider_models_response"
    public var requestId = ""
    public var provider: String
    public var cwd: String?
    public init(provider: String, cwd: String? = nil) {
        self.provider = provider
        self.cwd = cwd
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var provider: String
        public var models: [AgentModelDefinition]?
        public var error: String?
        public var fetchedAt: String?
    }
}

// Source: messages.ts `ListProviderModesRequestMessageSchema`

public struct ListProviderModesRequest: PaseoRequest {
    public static let type = "list_provider_modes_request"
    public static let responseType = "list_provider_modes_response"
    public var requestId = ""
    public var provider: String
    public var cwd: String?
    public init(provider: String, cwd: String? = nil) {
        self.provider = provider
        self.cwd = cwd
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var provider: String
        public var modes: [AgentMode]?
        public var error: String?
        public var fetchedAt: String?
    }
}

// Source: messages.ts `ListAvailableProvidersRequestMessageSchema`

/// Binary availability probe (CLI present, auth checks pass). Does not imply models can be created.
public struct ListAvailableProvidersRequest: PaseoRequest {
    public static let type = "list_available_providers_request"
    public static let responseType = "list_available_providers_response"
    public var requestId = ""
    public init() {}

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var providers: [Availability]
        public var error: String?
        public var fetchedAt: String?

        public struct Availability: Decodable, Sendable, Hashable {
            public var provider: String
            public var available: Bool
            public var error: String?
        }
    }
}
