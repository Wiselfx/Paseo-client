import Foundation

// Provider-managed subagents. Source: messages.ts `ProviderSubagentDescriptorPayloadSchema`,
// `ProviderSubagentListRequestMessageSchema`, `ProviderSubagentListResponseMessageSchema`,
// `ProviderSubagentUpdateMessageSchema`, `ProviderSubagentTimelineRequestMessageSchema`.
//
// A provider subagent id is not a Paseo agent id: rows are read-only. Paseo-managed subagents are
// ordinary agents carrying `paseo.parent-agent-id`; see `HostSession.subagents(of:)`.

public struct ProviderSubagent: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var parentAgentId: String
    /// Present only on daemons with `providerSubagentNesting`.
    public var parentSubagentId: String?
    public var provider: String
    public var title: String?
    public var description: String?
    public var status: Status
    public var createdAt: String
    public var updatedAt: String
    public var toolCallId: String?
    public var cwd: String?
    /// Provider-owned display text. Never parse provider facts out of it.
    public var subtitle: String?

    public enum Status: Sendable, Hashable, Decodable {
        case running, completed, failed, canceled
        case unknown(String)

        public init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "running": self = .running
            case "completed": self = .completed
            case "failed": self = .failed
            case "canceled": self = .canceled
            case let other: self = .unknown(other)
            }
        }
    }
}

public struct ProviderSubagentListRequest: PaseoRequest {
    public static let type = "agent.provider_subagents.list.request"
    public static let responseType = "agent.provider_subagents.list.response"
    public var requestId = ""
    public var parentAgentId: String

    public init(parentAgentId: String) {
        self.parentAgentId = parentAgentId
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var parentAgentId: String
        public var subagents: [ProviderSubagent]
        public var error: String?
    }
}

/// Unsolicited `agent.provider_subagents.update`. The daemon only streams these to clients that
/// advertise the `providerSubagents` capability.
public struct ProviderSubagentUpdate: Decodable, Sendable {
    /// The payload is a discriminated union on `kind`.
    public var subscriptionId: String?
    public var kind: Kind

    private enum K: String, CodingKey { case subscriptionId, kind, subagent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        switch try c.decode(String.self, forKey: .kind) {
        case "upsert":
            kind = .upsert(try c.decode(ProviderSubagent.self, forKey: .subagent))
        case "timeline":
            kind = .timeline(try Timeline(from: decoder))
        case "remove":
            kind = .remove(try Remove(from: decoder))
        case let other:
            kind = .unknown(kind: other)
        }
    }

    public enum Kind: Sendable {
        /// A subagent was added or its descriptor changed.
        case upsert(ProviderSubagent)
        /// One provider timeline row. This ticket keeps the list live; a timeline view can decode
        /// these from the same event.
        case timeline(Timeline)
        case remove(Remove)
        case unknown(kind: String)
    }

    public struct Timeline: Decodable, Sendable {
        public var parentAgentId: String
        public var subagentId: String
        public var provider: String
        public var item: TimelineItem
        public var timestamp: String
        public var seq: Int
        public var epoch: String
    }

    public struct Remove: Decodable, Sendable {
        public var parentAgentId: String
        public var subagentId: String
    }
}

/// Paged provider timeline. The list is the deliverable for T12; this type pins the wire shape so
/// a timeline screen does not need to touch PaseoKit.
public struct ProviderSubagentTimelineRequest: PaseoRequest {
    public static let type = "agent.provider_subagents.timeline.get.request"
    public static let responseType = "agent.provider_subagents.timeline.get.response"
    public var requestId = ""
    public var parentAgentId: String
    public var subagentId: String
    public var direction: Direction?
    public var cursor: TimelineCursor?
    public var limit: Int?

    public enum Direction: String, Encodable, Sendable { case tail, before, after }

    public init(
        parentAgentId: String, subagentId: String, direction: Direction? = nil,
        cursor: TimelineCursor? = nil, limit: Int? = nil
    ) {
        self.parentAgentId = parentAgentId
        self.subagentId = subagentId
        self.direction = direction
        self.cursor = cursor
        self.limit = limit
    }

    /// Same page shape as the main timeline (`FetchAgentTimelineRequest.Response`), kept as its own
    /// type because the daemon's provider page may evolve independently.
    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var parentAgentId: String
        public var subagentId: String
        public var provider: String?
        public var epoch: String
        public var reset: Bool?
        public var gap: Bool?
        public var entries: [TimelineEntry]
        public var hasOlder: Bool?
        public var hasNewer: Bool?
        public var startCursor: TimelineCursor?
        public var endCursor: TimelineCursor?
        public var error: String?
    }
}
