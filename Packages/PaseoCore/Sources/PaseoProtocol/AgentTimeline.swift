import Foundation

// Source: messages.ts fetch_agent_timeline_*, agent.timeline.set_subscription.*, agent_stream,
// AgentStreamEventPayloadSchema. Read docs/timeline-sync.md upstream for the sync contract.

public struct FetchAgentTimelineRequest: PaseoRequest {
    public static let type = "fetch_agent_timeline_request"
    public static let responseType = "fetch_agent_timeline_response"
    public var requestId = ""
    public var agentId: String
    public var direction: Direction
    public var cursor: TimelineCursor?
    /// Projected-item target. 0 means everything in the window.
    public var limit: Int?
    public var projection = "projected"
    /// Keep whole turns on tail/before pages.
    public var wholeTurns: Bool? = true

    public enum Direction: String, Encodable, Sendable, Decodable { case tail, before, after }

    public init(agentId: String, direction: Direction, cursor: TimelineCursor? = nil, limit: Int? = 40) {
        self.agentId = agentId; self.direction = direction; self.cursor = cursor; self.limit = limit
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        public var agent: AgentSnapshot?
        public var direction: Direction
        /// Timeline identity. A different epoch than the one you hold means: discard and reload.
        public var epoch: String
        /// True when the daemon could not continue from your cursor; replace your rows.
        public var reset: Bool
        public var staleCursor: Bool
        public var gap: Bool
        public var window: Window
        public var startCursor: TimelineCursor?
        public var endCursor: TimelineCursor?
        public var hasOlder: Bool
        public var hasNewer: Bool
        public var entries: [TimelineEntry]
        public var error: String?

        public struct Window: Decodable, Sendable, Hashable {
            public var minSeq: Int
            public var maxSeq: Int
            /// The seq the next live event will carry.
            public var nextSeq: Int
        }
    }
}

/// Replaces this session's set of streamed agents. Send the full set every time.
public struct SetAgentTimelineSubscriptionRequest: PaseoRequest {
    public static let type = "agent.timeline.set_subscription.request"
    public static let responseType = "agent.timeline.set_subscription.response"
    public var requestId = ""
    public var agentIds: [String]
    public init(agentIds: [String]) { self.agentIds = agentIds }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentIds: [String]
    }
}

/// Payload of an unsolicited `agent_stream` message.
public struct AgentStreamPayload: Decodable, Sendable {
    public var agentId: String
    public var event: AgentStreamEvent
    public var timestamp: String
    /// Present on `.timeline` events. Consecutive per epoch; a jump means you missed events
    /// and must catch up with `FetchAgentTimelineRequest(direction: .after)`.
    public var seq: Int?
    public var epoch: String?
}

public enum AgentStreamEvent: Sendable, Decodable {
    case turnStarted(turnId: String?)
    case turnCompleted(turnId: String?)
    case turnFailed(turnId: String?, error: String)
    case turnCanceled(turnId: String?, reason: String)
    /// A live delta. Unlike `TimelineEntry`, these are NOT merged: reasoning and assistant text
    /// arrive as many small chunks, and a tool call is re-sent each time its status changes.
    case timeline(item: TimelineItem, turnId: String?)
    case permissionRequested(raw: JSONValue)
    case permissionResolved(requestId: String)
    case attentionRequired(reason: String)
    case unknown(type: String)

    private enum K: String, CodingKey { case turnId, error, reason, item, request, requestId }

    public init(from decoder: Decoder) throws {
        let type = try decoder.discriminator()
        let c = try decoder.container(keyedBy: K.self)
        let turnId = try c.decodeIfPresent(String.self, forKey: .turnId)
        switch type {
        case "turn_started": self = .turnStarted(turnId: turnId)
        case "turn_completed": self = .turnCompleted(turnId: turnId)
        case "turn_failed": self = .turnFailed(turnId: turnId, error: try c.decode(String.self, forKey: .error))
        case "turn_canceled": self = .turnCanceled(turnId: turnId, reason: try c.decode(String.self, forKey: .reason))
        case "timeline": self = .timeline(item: try c.decode(TimelineItem.self, forKey: .item), turnId: turnId)
        case "permission_requested": self = .permissionRequested(raw: try c.decode(JSONValue.self, forKey: .request))
        case "permission_resolved": self = .permissionResolved(requestId: try c.decode(String.self, forKey: .requestId))
        case "attention_required": self = .attentionRequired(reason: try c.decode(String.self, forKey: .reason))
        default: self = .unknown(type: type)
        }
    }
}
