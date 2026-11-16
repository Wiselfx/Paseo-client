import Foundation

// Source: agent-labels.ts `PARENT_SERVER_ID_LABEL`, `PARENT_AGENT_ID_LABEL`,
// `getParentAgentIdFromLabels`.

/// The labels a Paseo-managed (delegated) agent carries to name its parent. These are ordinary
/// agents the daemon spawned for another agent, not provider subagents (which have no agent rows
/// and no labels). Detaching an agent clears the parent labels (`agent.detach.request`).
public enum AgentParentLabel {
    /// `PARENT_AGENT_ID_LABEL`.
    public static let agentId = "paseo.parent-agent-id"
    /// `PARENT_SERVER_ID_LABEL`. Absent means "the same host".
    public static let serverId = "paseo.parent-server-id"

    /// The parent agent id an agent names, or nil when it is not a subagent. Blank values do not
    /// count (`getParentAgentIdFromLabels` trims and rejects empty strings).
    public static func parent(of labels: [String: String]?) -> String? {
        guard let value = labels?[agentId]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    /// The host a subagent's parent lives on, defaulting to its own host.
    public static func parentServer(
        of labels: [String: String]?, defaultingTo host: String
    ) -> String {
        guard let value = labels?[serverId]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return host }
        return value
    }
}
