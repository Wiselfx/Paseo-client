import Foundation

// Permission requests: the one place where the daemon blocks agent work on the user.
// Source: messages.ts `AgentPermissionRequestPayloadSchema`, `AgentPermissionResponseSchema`,
// `AgentPermissionActionSchema`, `AgentPermissionRequestMessageSchema`,
// `AgentPermissionResolvedMessageSchema`.

// Source: messages.ts `AgentPermissionRequestPayloadSchema`

/// One pending approval, as carried on `agent_permission_request` and in
/// `AgentSnapshot.pendingPermissions`.
public struct AgentPermissionRequest: Sendable, Hashable, Decodable, Identifiable {
    /// `tool`, `plan`, `question`, `mode`, `other`, or anything newer.
    public enum Kind: Sendable, Hashable {
        case tool, plan, question, mode, other
        case unknown(String)
    }

    /// Request id. Reused in `agent_permission_resolved` and in the response.
    public var id: String
    public var provider: String
    /// Tool or permission name, e.g. `Bash`, `OMP select`.
    public var name: String
    public var kind: Kind
    public var title: String?
    public var description: String?
    /// Raw provider input: tool arguments, or the question form for `kind == .question`.
    /// Provider-defined, so render it generically; never assume a shape.
    public var input: JSONValue?
    /// Normalized tool call when the daemon could build one.
    public var detail: ToolCallDetail?
    /// Provider hints for `updatedPermissions`. Applying them widens authority — show them, don't
    /// apply them blindly.
    public var suggestions: [JSONValue]?
    /// Answers the daemon offers as buttons. May be absent (question-style approvals).
    public var actions: [AgentPermissionAction]?
    /// Provider-specific extras, e.g. `planText`.
    public var metadata: JSONValue?

    private enum K: String, CodingKey {
        case id, provider, name, kind, title, description, input, detail, suggestions, actions, metadata
    }

    public init(
        id: String, provider: String, name: String, kind: Kind, title: String? = nil,
        description: String? = nil, input: JSONValue? = nil, detail: ToolCallDetail? = nil,
        suggestions: [JSONValue]? = nil, actions: [AgentPermissionAction]? = nil,
        metadata: JSONValue? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.kind = kind
        self.title = title
        self.description = description
        self.input = input
        self.detail = detail
        self.suggestions = suggestions
        self.actions = actions
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decode(String.self, forKey: .provider)
        name = try c.decode(String.self, forKey: .name)
        kind = AgentPermissionRequest.Kind(wire: try c.decodeIfPresent(String.self, forKey: .kind))
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        input = try c.decodeIfPresent(JSONValue.self, forKey: .input)
        // A detail shape this client doesn't know must not sink the whole request.
        detail = try? c.decodeIfPresent(ToolCallDetail.self, forKey: .detail)
        suggestions = try? c.decodeIfPresent([JSONValue].self, forKey: .suggestions)
        actions = try? c.decodeIfPresent([AgentPermissionAction].self, forKey: .actions)
        metadata = try? c.decodeIfPresent(JSONValue.self, forKey: .metadata)
    }
}

extension AgentPermissionRequest.Kind {
    init(wire: String?) {
        switch wire {
        case "tool": self = .tool
        case "plan": self = .plan
        case "question": self = .question
        case "mode": self = .mode
        case "other": self = .other
        case let other?: self = .unknown(other)
        case nil: self = .other
        }
    }
}

// Source: messages.ts `AgentPermissionActionSchema`

/// One button the daemon offers for a permission request.
public struct AgentPermissionAction: Sendable, Hashable, Decodable, Identifiable {
    public enum Behavior: Sendable, Hashable {
        case allow, deny
        case unknown(String)
    }

    public enum Variant: Sendable, Hashable {
        case primary, secondary, danger
        case unknown(String)
    }

    public enum Intent: Sendable, Hashable {
        case implement, implementResume, dismiss
        case unknown(String)
    }

    public var id: String
    public var label: String
    public var behavior: Behavior
    public var variant: Variant?
    public var intent: Intent?

    public init(
        id: String, label: String, behavior: Behavior, variant: Variant? = nil,
        intent: Intent? = nil
    ) {
        self.id = id
        self.label = label
        self.behavior = behavior
        self.variant = variant
        self.intent = intent
    }

    private enum K: String, CodingKey { case id, label, behavior, variant, intent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        behavior = switch try c.decodeIfPresent(String.self, forKey: .behavior) {
        case "allow": .allow
        case "deny": .deny
        case let other?: .unknown(other)
        case nil: .unknown("")
        }
        variant = try c.decodeIfPresent(String.self, forKey: .variant).map { raw in
            switch raw {
            case "primary": .primary
            case "secondary": .secondary
            case "danger": .danger
            default: .unknown(raw)
            }
        }
        intent = try c.decodeIfPresent(String.self, forKey: .intent).map { raw in
            switch raw {
            case "implement": .implement
            case "implement_resume": .implementResume
            case "dismiss": .dismiss
            default: .unknown(raw)
            }
        }
    }
}

// Source: messages.ts `AgentPermissionResponseSchema`

/// The user's answer. Discriminated on `behavior`; encoded exactly as
/// `agent_permission_response.response` expects it.
public enum AgentPermissionResponse: Sendable, Hashable, Encodable, Decodable {
    case allow(selectedActionId: String?, updatedInput: JSONValue?, updatedPermissions: [JSONValue]?)
    /// `interrupt` cancels the provider turn; without it the provider settles on its own.
    case deny(selectedActionId: String?, message: String?, interrupt: Bool?)
    case unknown(behavior: String, raw: JSONValue)

    public static func allowing(selectedActionId: String? = nil) -> AgentPermissionResponse {
        .allow(selectedActionId: selectedActionId, updatedInput: nil, updatedPermissions: nil)
    }

    public static func denying(
        selectedActionId: String? = nil, message: String? = nil, interrupt: Bool = false
    ) -> AgentPermissionResponse {
        .deny(selectedActionId: selectedActionId, message: message, interrupt: interrupt)
    }

    private enum K: String, CodingKey {
        case behavior, selectedActionId, updatedInput, updatedPermissions, message, interrupt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let behavior = try c.decode(String.self, forKey: .behavior)
        switch behavior {
        case "allow":
            self = .allow(
                selectedActionId: try c.decodeIfPresent(String.self, forKey: .selectedActionId),
                updatedInput: try? c.decodeIfPresent(JSONValue.self, forKey: .updatedInput),
                updatedPermissions: try? c.decodeIfPresent([JSONValue].self, forKey: .updatedPermissions))
        case "deny":
            self = .deny(
                selectedActionId: try c.decodeIfPresent(String.self, forKey: .selectedActionId),
                message: try c.decodeIfPresent(String.self, forKey: .message),
                interrupt: try c.decodeIfPresent(Bool.self, forKey: .interrupt))
        default:
            self = .unknown(behavior: behavior, raw: (try? JSONValue(from: decoder)) ?? .null)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .allow(let selectedActionId, let updatedInput, let updatedPermissions):
            try c.encode("allow", forKey: .behavior)
            try c.encodeIfPresent(selectedActionId, forKey: .selectedActionId)
            try c.encodeIfPresent(updatedInput, forKey: .updatedInput)
            try c.encodeIfPresent(updatedPermissions, forKey: .updatedPermissions)
        case .deny(let selectedActionId, let message, let interrupt):
            try c.encode("deny", forKey: .behavior)
            try c.encodeIfPresent(selectedActionId, forKey: .selectedActionId)
            try c.encodeIfPresent(message, forKey: .message)
            try c.encodeIfPresent(interrupt, forKey: .interrupt)
        case .unknown(let behavior, _):
            try c.encode(behavior, forKey: .behavior)
        }
    }
}

// Source: messages.ts `AgentPermissionRequestMessageSchema`

/// Payload of an unsolicited `agent_permission_request` message.
public struct AgentPermissionRequestEvent: Sendable, Decodable {
    public var agentId: String
    public var request: AgentPermissionRequest
}

// Source: messages.ts `AgentPermissionResolvedMessageSchema`

/// Payload of an unsolicited `agent_permission_resolved` message. Fires for every observing
/// client, including resolutions this client did not make (auto-accept, timeouts, another client).
public struct AgentPermissionResolvedEvent: Sendable, Decodable {
    public var agentId: String
    /// The `AgentPermissionRequest.id` that was answered.
    public var requestId: String
    public var resolution: AgentPermissionResponse?
}

// Source: messages.ts `AgentPermissionResponseMessageSchema`

/// Answers one pending permission request.
///
/// Gotcha: this message has **no RPC correlation id**. Its wire `requestId` field is the permission
/// request id, and the outcome arrives as `agent_permission_resolved`. `DaemonClient.send` would
/// overwrite `requestId` with a fresh correlation id and then wait for a response that never comes,
/// so this request is sent fire-and-forget and its `requestId` is never encoded.
public struct RespondToAgentPermissionRequest: PaseoRequest {
    public static let type = "agent_permission_response"
    public static let responseType = "agent_permission_resolved"

    /// Never encoded; see the type comment.
    public var requestId = ""
    public var agentId: String
    public var permissionRequestId: String
    public var response: AgentPermissionResponse

    public init(agentId: String, permissionRequestId: String, response: AgentPermissionResponse) {
        self.agentId = agentId
        self.permissionRequestId = permissionRequestId
        self.response = response
    }

    private enum WireKey: String, CodingKey { case agentId, requestId, response }

    /// Never awaited; present only because `PaseoRequest` requires a response type. The real
    /// outcome is `AgentPermissionResolvedEvent`.
    public struct Response: Decodable, Sendable {
        public var agentId: String?
        public var requestId: String?
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: WireKey.self)
        try c.encode(agentId, forKey: .agentId)
        try c.encode(permissionRequestId, forKey: .requestId)
        try c.encode(response, forKey: .response)
    }
}

extension AgentSnapshot {
    /// The snapshot's pending requests, typed. `AgentSnapshot.pendingPermissions` stays raw so a
    /// newer daemon's permission shape never breaks decoding the whole snapshot.
    public var permissionRequests: [AgentPermissionRequest] {
        pendingPermissions.compactMap { try? $0.decoded(as: AgentPermissionRequest.self) }
    }
}

extension JSONValue {
    /// Re-decodes a raw value (from an event's open-ended field) as a concrete wire type.
    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }
}
