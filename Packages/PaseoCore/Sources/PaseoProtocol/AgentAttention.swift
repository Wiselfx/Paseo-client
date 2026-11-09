import Foundation

// Attention events. Older daemons (the protocol level this client speaks) deliver
// `agent_attention_required` as an `attention_required` event inside `agent_stream`; the
// event carries the daemon's per-client notification plan. Modern daemons send a top-level
// `agent_attention_required` message instead, but only to clients that advertise
// `explicit_event_subscriptions` — this client deliberately does not, so it keeps the legacy
// shape. Source: messages.ts `AgentAttentionRequiredMessageSchema`, `AgentStreamEventPayload`;
// packages/server/src/server/websocket-server.ts `sendAgentAttention` (legacy branch).

/// `finished` / `error` / `permission`.
public enum AgentAttentionReason: Sendable, Hashable, Decodable {
    case finished
    case error
    case permission
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "finished": self = .finished
        case "error": self = .error
        case "permission": self = .permission
        case let other: self = .unknown(other)
        }
    }

    /// The wire spelling, for notification payloads and diagnostics.
    public var rawValue: String {
        switch self {
        case .finished: return "finished"
        case .error: return "error"
        case .permission: return "permission"
        case .unknown(let value): return value
        }
    }
}

/// The `notification` object the daemon composes for one attention transition. Present on both
/// the legacy stream event and the modern top-level message.
public struct AgentAttentionNotification: Sendable, Decodable, Equatable {
    public var title: String
    public var body: String
    /// Data a tap routes on. The daemon omits `workspaceId` when it could not resolve one.
    public var data: AgentAttentionNotificationData?

    public init(title: String, body: String, data: AgentAttentionNotificationData? = nil) {
        self.title = title
        self.body = body
        self.data = data
    }
}

public struct AgentAttentionNotificationData: Sendable, Decodable, Equatable {
    public var serverId: String?
    public var workspaceId: String?
    public var agentId: String?
    public var reason: AgentAttentionReason?

    public init(
        serverId: String? = nil, workspaceId: String? = nil, agentId: String? = nil,
        reason: AgentAttentionReason? = nil
    ) {
        self.serverId = serverId
        self.workspaceId = workspaceId
        self.agentId = agentId
        self.reason = reason
    }
}

/// Everything an `attention_required` stream event carries beyond its `.attentionRequired` case.
/// Decoded alongside `AgentStreamEvent` so the legacy event loses none of the daemon's plan.
public struct AgentAttentionDetail: Sendable, Decodable, Equatable {
    public var reason: AgentAttentionReason
    public var timestamp: String?
    /// The daemon's per-source decision. False means another client was elected (or this one is
    /// focused on the agent); the badge still updates from the agent snapshot.
    public var shouldNotify: Bool
    public var notification: AgentAttentionNotification?

    private enum K: String, CodingKey { case reason, timestamp, shouldNotify, notification }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        reason = try c.decodeIfPresent(AgentAttentionReason.self, forKey: .reason) ?? .unknown("")
        timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
        // Older daemons did not carry the plan. An explicit attention event is still worth a
        // notification, so absent means yes; the receiver can suppress it locally.
        shouldNotify = try c.decodeIfPresent(Bool.self, forKey: .shouldNotify) ?? true
        notification = try c.decodeIfPresent(AgentAttentionNotification.self, forKey: .notification)
    }

    public init(
        reason: AgentAttentionReason, timestamp: String? = nil, shouldNotify: Bool = true,
        notification: AgentAttentionNotification? = nil
    ) {
        self.reason = reason
        self.timestamp = timestamp
        self.shouldNotify = shouldNotify
        self.notification = notification
    }
}

/// The modern top-level `agent_attention_required` message. A socket that advertises
/// `owned_subscriptions` receives attention only this way: the daemon skips the
/// `attention_required` frame inside `agent_stream` for modern sources.
public struct AgentAttentionRequired: Sendable, Decodable, Equatable {
    public var subscriptionId: String?
    public var agentId: String
    public var reason: AgentAttentionReason
    public var timestamp: String
    public var shouldNotify: Bool
    public var notification: AgentAttentionNotification?
}
