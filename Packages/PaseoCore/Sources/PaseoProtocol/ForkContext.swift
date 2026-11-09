import Foundation

// Fork: copy the conversation up to a boundary into a new agent's context. Source:
// `AgentForkContextRequestMessageSchema` (messages.ts:2054),
// `AgentForkContextResponseMessageSchema` (messages.ts:5196).
//
// Gate: `server_info.features.agentForkContext`. `boundaryCursor` pins to a projected row's
// `seqEnd`; `boundaryMessageId` matches `assistant_message` rows only (activity-curator.ts),
// so this client always sends the cursor. The response carries a `text` attachment with
// `contextKind: "chat_history"` — forward it verbatim to `create_agent_request` and the fork
// seeds the new agent with the curated history.

public struct ForkContextRequest: PaseoRequest {
    public static let type = "agent.fork_context.request"
    public static let responseType = "agent.fork_context.response"
    public var requestId = ""
    public var agentId: String
    public var boundaryCursor: TimelineCursor?
    public var boundaryMessageId: String?

    public init(
        agentId: String, boundaryCursor: TimelineCursor? = nil, boundaryMessageId: String? = nil
    ) {
        self.agentId = agentId
        self.boundaryCursor = boundaryCursor
        self.boundaryMessageId = boundaryMessageId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String?
        public var agentId: String?
        /// The chat-history seed, verbatim for `create_agent_request`.
        public var attachment: AgentAttachment.TextAttachment?
        public var itemCount: Int?
        public var boundaryMessageId: String?
        public var boundaryCursor: TimelineCursor?
        public var error: String?

        private enum K: String, CodingKey {
            case requestId, agentId, attachment, itemCount, boundaryMessageId, boundaryCursor, error
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
            attachment = try c.decodeIfPresent(AgentAttachment.TextAttachment.self, forKey: .attachment)
            itemCount = try c.decodeIfPresent(Int.self, forKey: .itemCount)
            boundaryMessageId = try c.decodeIfPresent(String.self, forKey: .boundaryMessageId)
            boundaryCursor = try c.decodeIfPresent(TimelineCursor.self, forKey: .boundaryCursor)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}
