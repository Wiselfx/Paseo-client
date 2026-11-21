import AppIntents
import Foundation

/// Entities from the persisted directory: cached when offline, empty when the app
/// never connected. Suggested first: agents needing attention, then the rest.
struct AgentQuery: EntityQuery {
    func entities(for identifiers: [AgentEntity.ID]) async throws -> [AgentEntity] {
        let ids = Set(identifiers)
        return AgentDirectory.load().agents
            .filter { ids.contains($0.id) }
            .map(AgentEntity.init(entry:))
    }

    func suggestedEntities() async throws -> [AgentEntity] {
        // The "agents needing attention" query: attention first, newest
        // snapshot order after. Attention without a host is the cached set.
        let snapshot = AgentDirectory.load()
        let attention = Set(snapshot.attentionIds)
        let sorted = snapshot.agents.sorted {
            (attention.contains($0.id) ? 0 : 1, $0.title)
                < (attention.contains($1.id) ? 0 : 1, $1.title)
        }
        return sorted.map(AgentEntity.init(entry:))
    }
}

extension AgentQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [AgentEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try await suggestedEntities() }
        return AgentDirectory.load().agents
            .filter { $0.title.localizedStandardContains(needle) }
            .map(AgentEntity.init(entry:))
    }
}
