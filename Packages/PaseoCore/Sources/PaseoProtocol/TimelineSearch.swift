import Foundation

// In-conversation search. Source: messages.ts `AgentTimelineSearchRequestMessageSchema`,
// `AgentTimelineSearchResponseMessageSchema` (agent.timeline.search.*).
//
// The daemon searches projected user and assistant rows and returns locations, not text. The
// client loads each located message from the timeline and verifies the rendered occurrences.

public struct AgentTimelineSearchRequest: PaseoRequest {
    public static let type = "agent.timeline.search.request"
    public static let responseType = "agent.timeline.search.response"
    public var requestId = ""
    public var agentId: String
    public var query: String
    /// Resume after the last returned location's `seq`. Omit for the first page.
    public var cursor: Int?

    public init(agentId: String, query: String, cursor: Int? = nil) {
        self.agentId = agentId
        self.query = query
        self.cursor = cursor
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        /// Timeline identity at search time. A different epoch means search again.
        public var epoch: String
        public var locations: [Location]
        /// Non-nil when the daemon capped this page; ask again with this cursor.
        public var nextCursor: Int?
        public var error: String?
    }

    public struct Location: Decodable, Sendable, Hashable {
        /// `seqEnd` of the projected row that contains the match.
        public var seq: Int
        public var role: Role
        /// Estimated occurrences in the message; the client verifies against rendered text.
        /// Older daemons omit it.
        public var count: Int?

        public init(seq: Int, role: Role, count: Int? = nil) {
            self.seq = seq
            self.role = role
            self.count = count
        }
    }

    public enum Role: Sendable, Hashable, Decodable {
        case user, assistant
        case unknown(String)

        public init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "user": self = .user
            case "assistant": self = .assistant
            case let other: self = .unknown(other)
            }
        }
    }
}

/// One result page plus where to scroll. Returned by `ConversationSearch.run(_:)`.
public struct ConversationSearchResult: Sendable, Hashable {
    public var query: String
    public var epoch: String
    public var locations: [AgentTimelineSearchRequest.Location]
    /// Nil when this is the last page.
    public var nextCursor: Int?

    public init(
        query: String, epoch: String, locations: [AgentTimelineSearchRequest.Location],
        nextCursor: Int?
    ) {
        self.query = query
        self.epoch = epoch
        self.locations = locations
        self.nextCursor = nextCursor
    }
}
