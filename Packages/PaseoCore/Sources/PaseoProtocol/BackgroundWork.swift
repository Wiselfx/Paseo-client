import Foundation

// M7g: background shells/monitors the agent has running. Source: messages.ts
// `AgentBackgroundWorkItemSchema` (messages.ts:5047), the list/stop requests
// (`AgentBackgroundWorkListRequestMessageSchema` messages.ts:2024,
// `AgentBackgroundWorkStopRequestMessageSchema` messages.ts:2030), the list/stop responses
// (messages.ts:5061, :5071) and `AgentBackgroundWorkUpdateMessageSchema` (messages.ts:5083).
//
// Capability gates: `features.agentBackgroundWork` (messages.ts:3953) and, for stop,
// `features.agentBackgroundWorkStop` (messages.ts:3955). A daemon without the gate answers
// every background-work request with `rpc_error` / `unknown_schema` — the store refuses the
// call client-side when the gate reads false.

/// One item of background work. `kind` is an open string; known values include `shell` and
/// `monitor`; unknown values are carried verbatim (clients treat them as "other").
public struct BackgroundWorkItem: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var kind: String
    public var description: String?
    public var command: String?
    /// ISO-8601, from the daemon.
    public var startedAt: String
    public var canStop: Bool?
    public var stopToken: String?

    public init(
        id: String, kind: String, description: String? = nil, command: String? = nil,
        startedAt: String, canStop: Bool? = nil, stopToken: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.description = description
        self.command = command
        self.startedAt = startedAt
        self.canStop = canStop
        self.stopToken = stopToken
    }

    private enum K: String, CodingKey {
        case id, kind, description, command, startedAt, canStop, stopToken
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        description = try c.decodeIfPresent(String.self, forKey: .description)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt) ?? ""
        canStop = try c.decodeIfPresent(Bool.self, forKey: .canStop)
        stopToken = try c.decodeIfPresent(String.self, forKey: .stopToken)
    }
}

public struct BackgroundWorkListRequest: PaseoRequest {
    public static let type = "agent.background_work.list.request"
    public static let responseType = "agent.background_work.list.response"
    public var requestId = ""
    public var agentId: String

    public init(agentId: String) {
        self.agentId = agentId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var agentId: String
        public var items: [BackgroundWorkItem]
        public var error: String?

        private enum K: String, CodingKey { case requestId, agentId, items, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? ""
            items = try c.decodeIfPresent([BackgroundWorkItem].self, forKey: .items) ?? []
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

public struct BackgroundWorkStopRequest: PaseoRequest {
    public static let type = "agent.background_work.stop.request"
    public static let responseType = "agent.background_work.stop.response"
    public var requestId = ""
    public var agentId: String
    public var itemId: String
    public var stopToken: String

    public init(agentId: String, itemId: String, stopToken: String) {
        self.agentId = agentId
        self.itemId = itemId
        self.stopToken = stopToken
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String?
        public var agentId: String?
        public var itemId: String?
        public var error: String?

        private enum K: String, CodingKey { case requestId, agentId, itemId, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
            itemId = try c.decodeIfPresent(String.self, forKey: .itemId)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

/// Unsolicited `agent.background_work.update`; each push replaces the agent's whole list.
public struct BackgroundWorkUpdate: Decodable, Sendable {
    public var subscriptionId: String?
    public var agentId: String
    public var items: [BackgroundWorkItem]

    private enum K: String, CodingKey { case subscriptionId, agentId, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId) ?? ""
        items = try c.decodeIfPresent([BackgroundWorkItem].self, forKey: .items) ?? []
    }
}
