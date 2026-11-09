import Foundation

// Agent control: create, mode/model/thinking switches, rename, archive, stop, attention.
// Source: messages.ts `CreateAgentRequestMessageSchema`, `AgentSessionConfigSchema`,
// `SetAgentModeRequestMessageSchema`, `SetAgentModelRequestMessageSchema`,
// `SetAgentThinkingRequestMessageSchema`, `UpdateAgentRequestMessageSchema`,
// `ArchiveAgentRequestMessageSchema`, `AgentActionResponsePayloadSchema`,
// `AgentCreatedStatusPayloadSchema`, `AgentCreateFailedStatusPayloadSchema`,
// `ClearAgentAttentionMessageSchema`, `ClearAgentAttentionResponseMessageSchema`,
// `AgentSnapshotPayloadSchema.attentionReason`.

// Source: messages.ts `AgentProviderNoticeSchema`

/// A notice the provider attaches to an accepted change: usually "staged for the next turn".
public struct AgentProviderNotice: Sendable, Hashable, Decodable {
    public enum Level: Sendable, Hashable {
        case info, warning, error
        case unknown(String)
    }

    public var level: Level
    public var message: String

    private enum K: String, CodingKey { case type, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        level = switch try c.decodeIfPresent(String.self, forKey: .type) {
        case "info": .info
        case "warning": .warning
        case "error": .error
        case let other?: .unknown(other)
        case nil: .unknown("")
        }
        message = try c.decode(String.self, forKey: .message)
    }
}

// Source: messages.ts `AgentActionResponsePayloadSchema`

/// Shared payload of `set_agent_mode_response`, `set_agent_model_response`,
/// `set_agent_thinking_response` and `update_agent_response`.
public struct AgentActionResponse: Decodable, Sendable {
    public var requestId: String
    public var agentId: String
    public var accepted: Bool
    public var error: String?
    public var notice: AgentProviderNotice?
}

// Source: messages.ts `AgentSessionConfigSchema`

/// `AgentSessionConfigSchema`. Reused for creation and (upstream) resume overrides.
public struct AgentSessionConfig: Encodable, Sendable {
    public var provider: String
    public var cwd: String
    public var modeId: String?
    public var model: String?
    public var thinkingOptionId: String?
    /// Provider feature values applied at creation (e.g. from an agent profile);
    /// `AgentSessionConfigSchema.featureValues`, messages.ts:511.
    public var featureValues: [String: JSONValue]?
    public var title: String?
    public var systemPrompt: String?

    public init(
        provider: String, cwd: String, modeId: String? = nil, model: String? = nil,
        thinkingOptionId: String? = nil, featureValues: [String: JSONValue]? = nil,
        title: String? = nil, systemPrompt: String? = nil
    ) {
        self.provider = provider
        self.cwd = cwd
        self.modeId = modeId
        self.model = model
        self.thinkingOptionId = thinkingOptionId
        self.featureValues = featureValues
        self.title = title
        self.systemPrompt = systemPrompt
    }
}

// Source: messages.ts `CreateAgentRequestMessageSchema`, `AgentCreatedStatusPayloadSchema`,
// `AgentCreateFailedStatusPayloadSchema`

/// Creates one agent, optionally with its first prompt, inside an existing workspace.
///
/// The daemon answers on the `status` stream with `agent_created` or `agent_create_failed`, both
/// correlated by `requestId`; `Response` decodes either. The modern `agent.create.request` path
/// (receipts, caller-chosen ids) is not used here.
public struct CreateAgentRequest: PaseoRequest {
    public static let type = "create_agent_request"
    public static let responseType = "status"
    public var requestId = ""
    public var config: AgentSessionConfig
    public var initialPrompt: String?
    /// Placement. Omitting it uses the caller's workspace; `cwd` still decides the runtime.
    public var workspaceId: String?
    public var labels: [String: String]?
    /// Structured attachments, e.g. the `chat_history` fork seed (M7h). Encoded flat next to
    /// `initialPrompt`, omitting the key when nil.
    public var attachments: [AgentAttachment]?

    public init(
        config: AgentSessionConfig, initialPrompt: String? = nil, workspaceId: String? = nil,
        labels: [String: String]? = nil, attachments: [AgentAttachment]? = nil
    ) {
        self.config = config
        self.initialPrompt = initialPrompt
        self.workspaceId = workspaceId
        self.labels = labels
        self.attachments = attachments
    }

    /// Either `agent_created` (with `agent`) or `agent_create_failed` (with `error`).
    public struct Response: Decodable, Sendable {
        public var status: String
        public var requestId: String
        public var agentId: String?
        public var agent: AgentSnapshot?
        public var error: String?
        public var errorCode: String?
    }
}

// Source: messages.ts `SetAgentModeRequestMessageSchema`

public struct SetAgentModeRequest: PaseoRequest {
    public static let type = "set_agent_mode_request"
    public static let responseType = "set_agent_mode_response"
    public var requestId = ""
    public var agentId: String
    /// Mode ids are provider-defined and may be URIs; never shorten them.
    public var modeId: String
    public init(agentId: String, modeId: String) {
        self.agentId = agentId
        self.modeId = modeId
    }
    public typealias Response = AgentActionResponse
}

// Source: messages.ts `SetAgentModelRequestMessageSchema`

public struct SetAgentModelRequest: PaseoRequest {
    public static let type = "set_agent_model_request"
    public static let responseType = "set_agent_model_response"
    public var requestId = ""
    public var agentId: String
    /// `null` clears the override and falls back to the provider default.
    public var modelId: String?
    public init(agentId: String, modelId: String?) {
        self.agentId = agentId
        self.modelId = modelId
    }

    public typealias Response = AgentActionResponse

    private enum K: String, CodingKey { case requestId, agentId, modelId }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        // A hand-written encoder must carry the correlation id too: without it the daemon rejects
        // the frame as invalid and never answers, so the caller waits for its timeout.
        try c.encode(requestId, forKey: .requestId)
        try c.encode(agentId, forKey: .agentId)
        // The schema is `z.string().nullable()`: the key must be present even when clearing.
        if let modelId { try c.encode(modelId, forKey: .modelId) } else { try c.encodeNil(forKey: .modelId) }
    }
}

// Source: messages.ts `SetAgentThinkingRequestMessageSchema`

public struct SetAgentThinkingRequest: PaseoRequest {
    public static let type = "set_agent_thinking_request"
    public static let responseType = "set_agent_thinking_response"
    public var requestId = ""
    public var agentId: String
    /// `null` clears the override.
    public var thinkingOptionId: String?
    public init(agentId: String, thinkingOptionId: String?) {
        self.agentId = agentId
        self.thinkingOptionId = thinkingOptionId
    }

    public typealias Response = AgentActionResponse

    private enum K: String, CodingKey { case requestId, agentId, thinkingOptionId }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        // See SetAgentModelRequest: a hand-written encoder drops `requestId` unless it encodes it.
        try c.encode(requestId, forKey: .requestId)
        try c.encode(agentId, forKey: .agentId)
        if let thinkingOptionId {
            try c.encode(thinkingOptionId, forKey: .thinkingOptionId)
        } else {
            try c.encodeNil(forKey: .thinkingOptionId)
        }
    }
}

// Source: messages.ts `UpdateAgentRequestMessageSchema`

/// Rename (`name`) and/or merge labels (send only the keys to change).
public struct UpdateAgentRequest: PaseoRequest {
    public static let type = "update_agent_request"
    public static let responseType = "update_agent_response"
    public var requestId = ""
    public var agentId: String
    public var name: String?
    public var labels: [String: String]?
    public init(agentId: String, name: String? = nil, labels: [String: String]? = nil) {
        self.agentId = agentId
        self.name = name
        self.labels = labels
    }
    public typealias Response = AgentActionResponse
}

// Source: messages.ts `ArchiveAgentRequestMessageSchema`, `AgentArchivedMessageSchema`

/// Soft delete. There is no dedicated response message: the daemon broadcasts `agent_archived`,
/// correlated by `requestId`, and that is what resolves this request.
public struct ArchiveAgentRequest: PaseoRequest {
    public static let type = "archive_agent_request"
    public static let responseType = "agent_archived"
    public var requestId = ""
    public var agentId: String
    public init(agentId: String) { self.agentId = agentId }

    public struct Response: Decodable, Sendable {
        public var agentId: String
        public var archivedAt: String
        public var requestId: String?
    }
}

// Source: messages.ts `ClearAgentAttentionMessageSchema`, `ClearAgentAttentionResponseMessageSchema`

/// Clears unread attention for one agent. Deliberate focus does this; merely loading the runtime
/// does not. The daemon also pushes the cleared snapshots on the response.
public struct ClearAgentAttentionRequest: PaseoRequest {
    public static let type = "clear_agent_attention"
    public static let responseType = "clear_agent_attention_response"
    public var requestId = ""
    public var agentId: String
    public init(agentId: String) { self.agentId = agentId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agents: [AgentSnapshot]
    }
}

// Source: messages.ts `AgentSnapshotPayloadSchema.attentionReason`

/// Why the agent list shows an unread badge.
public enum AgentAttention: Sendable, Hashable {
    case finished, error, permission
    case unknown(String)

    public init?(wire: String?) {
        switch wire {
        case "finished": self = .finished
        case "error": self = .error
        case "permission": self = .permission
        case let other?: self = .unknown(other)
        case nil: return nil
        }
    }
}

extension AgentSnapshot {
    /// Typed `attentionReason`, only while the daemon still flags the agent as unread.
    public var attention: AgentAttention? {
        if requiresAttention == false { return nil }
        return AgentAttention(wire: attentionReason)
    }
}

extension Array where Element == AgentSnapshot {
    /// Agents with an unread badge, newest activity first (the list is already sorted).
    public var needingAttention: [AgentSnapshot] { filter { $0.attention != nil } }
}
