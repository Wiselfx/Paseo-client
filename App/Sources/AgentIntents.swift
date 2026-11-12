import AppIntents
import CoreSpotlight
import Foundation
import PaseoUI

// MARK: - Agent intents (Phase D G16)

// NOTE: App Intents and Spotlight live in the main app target — no extensions, no
// entitlements, no second router. Every navigation goes through the existing
// `paseo://` deep-link path (`OpenURLIntent` + the shell's router): intents never
// touch a session directly, so they work when no host is connected (cached/empty,
// never hang). Agent titles are the user's private data: entity display names
// follow the "Show agent names" toggle outside the app, while Spotlight indexes
// titles regardless — in-app search that never leaves the phone (see the toggle's
// comment for why).

/// The privacy toggle behind entity names and system surfaces. Off by default
/// (`bool(forKey:)` is false when unset).
private var showAgentNames: Bool {
    UserDefaults.standard.bool(forKey: PaseoSettingsKeys.showAgentNames)
}

/// One agent, resolved from the persisted directory at query time.
struct AgentEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Agents"

    var id: String
    var title: String
    var hostServerID: String

    static var defaultQuery = AgentQuery()

    var displayRepresentation: DisplayRepresentation {
        // Outside the app, names show only with opt-in. The toggle is read at
        // query time, so flipping it applies to the next lookup with no refresh.
        if showAgentNames {
            DisplayRepresentation(title: "\(title)")
        } else {
            DisplayRepresentation(title: "Agent")
        }
    }
}

/// Indexed for Spotlight: the system resolves tapped results back into entities.
extension AgentEntity: IndexedEntity {
    func attributeSet(for locale: Locale) -> CSSearchableItemAttributeSet? {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        return attributes
    }
}

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
    func entities(for string: String) async throws -> [AgentEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }
        return AgentDirectory.load().agents
            .filter { $0.title.lowercased().contains(needle) }
            .map(AgentEntity.init(entry:))
    }
}

private extension AgentEntity {
    init(entry: AgentDirectoryEntry) {
        // Display names follow the toggle at query time; the stored title stays
        // verbatim so flipping the toggle never loses data.
        let visible = showAgentNames ? entry.title : "Agent"
        self.init(id: entry.id, title: visible, hostServerID: entry.hostServerID)
    }
}

/// Opens the agent in the app through the existing deep-link route. Never sends.
struct OpenAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Open agent"
    static var description = IntentDescription("Open one of your agents.")
    static var openAppWhenRun = true

    @Parameter(title: "Agent")
    var agent: AgentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$agent)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard
            let url = URL(
                string: "paseo://h/\(agent.hostServerID)/agent/\(agent.id)")
        else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// Starts a new agent draft and focuses its composer. Never sends: creation stays
/// user-driven — the draft waits for the reader.
struct NewAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "New agent"
    static var description = IntentDescription("Start a new agent.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url = URL(string: "paseo://new-agent") else {
            throw URLError(.badURL)
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// App Shortcuts with plain names.
struct PaseoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAgentIntent(),
            phrases: [
                "Open \(\(.applicationName)) agent",
                "Show \(\(.applicationName)) agent",
            ],
            shortTitle: "Open agent",
            systemImageName: "message")
        AppShortcut(
            intent: NewAgentIntent(),
            phrases: [
                "New \(\(.applicationName)) agent",
                "Start \(\(.applicationName)) agent",
            ],
            shortTitle: "New agent",
            systemImageName: "plus.message")
    }
}
