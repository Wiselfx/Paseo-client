import Foundation

/// One row of the persisted snapshot: enough to open the agent and name it.
struct AgentDirectoryEntry: Codable, Sendable, Hashable {
    var id: String
    var title: String
    var hostServerID: String
}
