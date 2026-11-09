import Foundation

// The conversation's prompt index — what the chat outline (rail + "Jump to message") reads.
// Source: messages.ts `AgentTimelineListPromptsRequestMessageSchema` (:2012-2016) and
// `AgentTimelineListPromptsResponseMessageSchema` (:4998-5016), gated by the daemon feature
// `agentTimelinePromptIndex` (messages.ts:3912-3913, advertised at
// server/src/server/websocket-server.ts:2112-2113).
//
// The daemon builds the index from every projected `user_message` row of the *whole* conversation,
// loaded or not (`server/src/server/agent/timeline-prompt-index.ts:24-39`). Each `preview` is that
// prompt's text with runs of whitespace collapsed and truncated to 120 characters, ending in "…"
// (`timeline-prompt-index.ts:3-22`). `seq` is the prompt row's timeline position, so a jump can
// fetch the window around it without paging through the conversation.
//
// Forward compatibility: an older daemon answers with `epoch: ""`, no prompts and an `error`; a
// newer one may add fields. Neither may throw, so every field decodes tolerantly.

public struct AgentTimelinePromptIndexRequest: PaseoRequest {
    public static let type = "agent.timeline.list_prompts.request"
    public static let responseType = "agent.timeline.list_prompts.response"
    public var requestId = ""
    public var agentId: String

    public init(agentId: String) {
        self.agentId = agentId
    }

    public struct Response: Decodable, Sendable, Hashable {
        public var requestId: String
        public var agentId: String
        /// Timeline identity the index was built from. Never apply an index from another epoch.
        public var epoch: String
        /// Every user prompt, oldest first.
        public var prompts: [Prompt]
        public var error: String?

        private enum K: String, CodingKey { case requestId, agentId, epoch, prompts, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = (try? c.decode(String.self, forKey: .requestId)) ?? ""
            agentId = (try? c.decode(String.self, forKey: .agentId)) ?? ""
            epoch = (try? c.decode(String.self, forKey: .epoch)) ?? ""
            prompts = (try? c.decode([Prompt].self, forKey: .prompts)) ?? []
            error = try? c.decodeIfPresent(String.self, forKey: .error)
        }

        /// One prompt. `seq` is the `seqStart` of its projected user row.
        public struct Prompt: Decodable, Sendable, Hashable, Identifiable {
            public var seq: Int
            public var timestamp: String
            /// Text with whitespace collapsed and at most 120 characters (the daemon's own cut).
            public var preview: String

            public var id: Int { seq }

            public init(seq: Int, timestamp: String, preview: String) {
                self.seq = seq
                self.timestamp = timestamp
                self.preview = preview
            }
        }
    }
}
