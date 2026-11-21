import Foundation

/// The persisted snapshot: the agent list plus the ids currently needing attention.
struct AgentDirectorySnapshot: Codable, Sendable {
    var agents: [AgentDirectoryEntry]
    var attentionIds: [String]
}
