import Foundation

// Provider feature switches, live on a running agent. Source: messages.ts
// `SetAgentFeatureRequestSchema` (`set_agent_feature_request`, :2106), response
// `set_agent_feature_response` (:2114) carrying the shared `AgentActionResponse` payload
// (`messages.ts:2069`). The features themselves are listed on the snapshot
// (`AgentSnapshotPayloadSchema.features`) and by `list_provider_features_request`.

/// Source: messages.ts `SetAgentFeatureRequestMessageSchema` (`set_agent_feature_request`).
public struct SetAgentFeatureRequest: PaseoRequest {
    public static let type = "set_agent_feature_request"
    public static let responseType = "set_agent_feature_response"
    public var requestId = ""
    public var agentId: String
    public var featureId: String
    /// Encoded verbatim: `.bool(_)` for toggles, `.string(_)` / `.null` for selects.
    public var value: JSONValue

    public init(agentId: String, featureId: String, value: JSONValue) {
        self.agentId = agentId
        self.featureId = featureId
        self.value = value
    }

    public typealias Response = AgentActionResponse
}
