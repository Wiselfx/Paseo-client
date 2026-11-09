import Foundation

// Agent lifecycle beyond the message stream: the history listing (live + archived, with cursor
// paging), permanent delete, and unarchive (refresh). Rename and archive already exist
// (`UpdateAgentRequest`, `ArchiveAgentRequest`).
// Source: messages.ts `FetchAgentHistoryRequestMessageSchema` (`fetch_agent_history_request`, :1420),
// `FetchAgentHistoryResponseMessageSchema` (:4474), `AgentDirectoryResponseEntrySchema` (:4445),
// `AgentDirectoryPageInfoSchema` (:4457), `FetchAgentsResponseMessageSchema` searchTruncated (:4477).

// MARK: - History listing

/// Source: messages.ts `FetchAgentHistoryRequestMessageSchema` (`fetch_agent_history_request`).
/// Includes archived agents by default (the server forces `includeArchived: true` when it is
/// absent). `search` is a free-text filter over title, workspace name, branch and project name.
public struct FetchAgentHistoryRequest: PaseoRequest {
    public static let type = "fetch_agent_history_request"
    public static let responseType = "fetch_agent_history_response"
    public var requestId = ""
    public var search: String?
    public var page: Page?
    public var sort: [Sort]?

    public init(search: String? = nil, page: Page? = nil, sort: [Sort]? = nil) {
        self.search = search
        self.page = page
        self.sort = sort ?? [Sort(key: "updated_at", direction: "desc")]
    }

    public struct Page: Encodable, Sendable {
        public var limit: Int
        public var cursor: String?
        public init(limit: Int, cursor: String? = nil) {
            self.limit = limit
            self.cursor = cursor
        }
    }

    public struct Sort: Encodable, Sendable {
        public var key: String
        public var direction: String
        public init(key: String, direction: String) {
            self.key = key
            self.direction = direction
        }
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var entries: [FetchAgentsRequest.Response.Entry]
        public var pageInfo: PageInfo
        public var searchTruncated: Bool?

        public struct PageInfo: Decodable, Sendable {
            public var nextCursor: String?
            public var prevCursor: String?
            public var hasMore: Bool
        }
    }
}

// MARK: - Delete

/// Source: messages.ts `DeleteAgentRequestMessageSchema` (`delete_agent_request`, :993); the
/// daemon correlates the response as `agent_deleted` (:5546). Permanent — there is no undo.
public struct DeleteAgentRequest: PaseoRequest {
    public static let type = "delete_agent_request"
    public static let responseType = "agent_deleted"
    public var requestId = ""
    public var agentId: String

    public init(agentId: String) { self.agentId = agentId }

    public struct Response: Decodable, Sendable {
        public var agentId: String
        public var requestId: String
    }
}

// MARK: - Unarchive

/// Source: messages.ts `RefreshAgentRequestMessageSchema` (`refresh_agent_request`, :1949),
/// response `AgentRefreshedStatusPayloadSchema` (`agent_refreshed`, :4100). The upstream app uses
/// `refreshAgent` to unarchive an agent (`packages/app/src/components/archived-agent-callout.tsx`).
public struct RefreshAgentRequest: PaseoRequest {
    public static let type = "refresh_agent_request"
    public static let responseType = "status"
    public var requestId = ""
    public var agentId: String

    public init(agentId: String) { self.agentId = agentId }

    public struct Response: Decodable, Sendable {
        public var status: String
        public var requestId: String
        public var timelineSize: Int?
    }
}
