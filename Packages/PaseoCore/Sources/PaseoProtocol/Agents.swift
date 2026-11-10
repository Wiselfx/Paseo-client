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
    /// Requested thinking level; `nil` means the provider default. Added by T6 (agent control).
    public var thinkingOptionId: String?
    /// The level the provider actually runs, which may be downgraded from `thinkingOptionId`.
    public var effectiveThinkingOptionId: String?
    public var title: String?
    public var status: AgentStatus
    public var createdAt: String
    public var updatedAt: String
    public var lastUserMessageAt: String?
    /// Provider capability flags carried on the wire (`capabilities`, messages.ts:417-433). Nil
    /// when the daemon doesn't send them.
    public var capabilities: AgentCapabilities?
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
    /// Provider-specific feature toggles/selects (e.g. `fast_mode`), from
    /// `AgentSnapshotPayloadSchema.features`. Optional: absent on older daemons and for
    /// providers without features.
    public var features: [AgentFeature]?
    /// Context-window and cost figures the provider reports; refreshed with the snapshot and
    /// merged context-window fields from stream usage events.
    public var lastUsage: AgentUsage?

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
    /// `active` keeps the directory to agents placed in an active workspace, so archived rows
    /// cannot push active ones off a page (messages.ts:1332). Optional: older hosts strip it.
    public var scope: String?
    /// Include agents living in background workspaces. Optional, and only sent when the host
    /// advertises `backgroundWorkspaces` (upstream `supportsBackgroundWorkspaces()`).
    public var includeBackground: Bool?
    /// Directory order, applied before the page is cut (messages.ts:1335-1342).
    public var sort: [Sort]?

    /// The server caps a page at 200 rows (messages.ts:1345).
    public static let maxPageLimit = 200

    public struct Page: Encodable, Sendable, Equatable {
        public var limit: Int
        public var cursor: String?
        public init(limit: Int, cursor: String? = nil) { self.limit = limit; self.cursor = cursor }
    }
    public struct Subscribe: Encodable, Sendable { public init() {} }
    public struct Sort: Encodable, Sendable, Equatable {
        public var key: String
        public var direction: String
        public init(key: String, direction: String) {
            self.key = key
            self.direction = direction
        }
        /// What upstream sends: `[{ key: "updated_at", direction: "desc" }]`.
        public static let updatedAtDescending = Sort(key: "updated_at", direction: "desc")
    }

    public init(
        page: Page? = Page(limit: 100), subscribe: Bool = false, scope: String? = nil,
        includeBackground: Bool? = nil, sort: [Sort]? = nil
    ) {
        self.page = page
        self.subscribe = subscribe ? Subscribe() : nil
        self.scope = scope
        self.includeBackground = includeBackground
        self.sort = sort
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        /// Present when the request subscribed. On a modern socket it is the server-assigned
        /// id used to release the subscription (`subscription.release.request`); legacy
        /// daemons also send their locally chosen id.
        public var subscriptionId: String?
        public var entries: [Entry]
        /// Absent on hosts that predate paging: one page, nothing more to read.
        public var pageInfo: PageInfo?
        public struct Entry: Decodable, Sendable {
            public var agent: AgentSnapshot
            public var project: ProjectPlacement?
        }

        /// Source: `AgentDirectoryPageInfoSchema` (messages.ts:4457-4461).
        public struct PageInfo: Decodable, Sendable {
            public var nextCursor: String?
            public var prevCursor: String?
            public var hasMore: Bool?
            /// Older spellings the reference client still reads
            /// (`resolveAgentNextPage`, directory-sync/index.ts:46-53).
            public var afterCursor: String?
            public var hasMoreAfter: Bool?

            /// The next page's cursor, or nil when this was the last page.
            public var cursorForNextPage: String? {
                guard hasMore ?? hasMoreAfter ?? false else { return nil }
                return nextCursor ?? afterCursor
            }
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
    /// Inline base64 images. Text-only provider models reject these, so prefer a file attachment
    /// and a path hint for those providers.
    public var images: [ImageAttachment]?
    /// Structured attachments (`text`, `review`, `uploaded_file`, forge links).
    public var attachments: [AgentAttachment]?

    public init(
        agentId: String, text: String, messageId: String? = nil, activeTurnBehavior: String? = nil,
        images: [ImageAttachment]? = nil, attachments: [AgentAttachment]? = nil
    ) {
        self.agentId = agentId; self.text = text; self.messageId = messageId
        self.activeTurnBehavior = activeTurnBehavior; self.images = images; self.attachments = attachments
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
