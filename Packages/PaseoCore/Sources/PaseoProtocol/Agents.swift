import Foundation

// Source: messages.ts `AgentSnapshotPayloadSchema`, `AGENT_LIFECYCLE_STATUSES`, fetch_agents_*,
// agent_update, send_agent_message_*, cancel_agent_*. Fields are a subset; add as features need them.

public enum AgentStatus: Sendable, Hashable, Decodable {
    case initializing, idle, running, error, closed
    case unknown(String)
    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "initializing": self = .initializing
        case "idle": self = .idle
        case "running": self = .running
        case "error": self = .error
        case "closed": self = .closed
        case let other: self = .unknown(other)
        }
    }
}

public struct AgentMode: Sendable, Hashable, Decodable {
    public var id: String
    public var label: String
    public var description: String?
    public var icon: String?
}

public struct AgentSnapshot: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    /// Provider id, e.g. `claude`, `opencode`, `pi`. Open set: new providers appear without a client update.
    public var provider: String
    public var cwd: String
    public var workspaceId: String?
    public var model: String?
    public var title: String?
    public var status: AgentStatus
    public var createdAt: String
    public var updatedAt: String
    public var lastUserMessageAt: String?
    public var activeTurn: ActiveTurn?
    public var currentModeId: String?
    public var availableModes: [AgentMode]
    /// Typed when the permissions feature lands; kept raw so the snapshot always decodes.
    public var pendingPermissions: [JSONValue]
    public var lastError: String?
    public var requiresAttention: Bool?
    /// `finished`, `error`, `permission`.
    public var attentionReason: String?
    public var archivedAt: String?
    public var labels: [String: String]?

    public struct ActiveTurn: Sendable, Hashable, Decodable {
        public var turnId: String
        public var startedAt: String?
    }
}

/// Project placement attached to agent rows. Subset.
public struct ProjectPlacement: Sendable, Hashable, Decodable {
    public var projectKey: String
    public var projectName: String
    public var workspaceName: String?
}

public struct FetchAgentsRequest: PaseoRequest {
    public static let type = "fetch_agents_request"
    public static let responseType = "fetch_agents_response"
    public var requestId = ""
    public var page: Page?
    /// Present to also receive live `agent_update` messages for this session.
    public var subscribe: Subscribe?

    public struct Page: Encodable, Sendable {
        public var limit: Int
        public var cursor: String?
        public init(limit: Int, cursor: String? = nil) { self.limit = limit; self.cursor = cursor }
    }
    public struct Subscribe: Encodable, Sendable { public init() {} }

    public init(page: Page? = Page(limit: 100), subscribe: Bool = false) {
        self.page = page
        self.subscribe = subscribe ? Subscribe() : nil
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var entries: [Entry]
        public struct Entry: Decodable, Sendable {
            public var agent: AgentSnapshot
            public var project: ProjectPlacement?
        }
    }
}

/// Live directory change, delivered after `FetchAgentsRequest(subscribe: true)`.
public enum AgentUpdate: Sendable, Decodable {
    case upsert(AgentSnapshot, project: ProjectPlacement?)
    case remove(agentId: String)
    case unknown(kind: String)

    private enum K: String, CodingKey { case kind, agent, project, agentId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "upsert": self = .upsert(try c.decode(AgentSnapshot.self, forKey: .agent), project: try c.decodeIfPresent(ProjectPlacement.self, forKey: .project))
        case "remove": self = .remove(agentId: try c.decode(String.self, forKey: .agentId))
        case let other: self = .unknown(kind: other)
        }
    }
}

public struct SendAgentMessageRequest: PaseoRequest {
    public static let type = "send_agent_message_request"
    public static let responseType = "send_agent_message_response"
    public var requestId = ""
    public var agentId: String
    public var text: String
    /// Client-generated id; the daemon echoes it as `clientMessageId` on the user_message row,
    /// which is how an optimistic bubble is matched to the real one.
    public var messageId: String?
    /// `steer` or `interrupt` when the agent is mid-turn.
    public var activeTurnBehavior: String?

    public init(agentId: String, text: String, messageId: String? = nil, activeTurnBehavior: String? = nil) {
        self.agentId = agentId; self.text = text; self.messageId = messageId; self.activeTurnBehavior = activeTurnBehavior
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        public var accepted: Bool
        public var error: String?
    }
}

public struct CancelAgentRequest: PaseoRequest {
    public static let type = "cancel_agent_request"
    public static let responseType = "cancel_agent_response"
    public var requestId = ""
    public var agentId: String
    public init(agentId: String) { self.agentId = agentId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        public var error: String?
    }
}
