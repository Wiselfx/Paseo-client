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
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Agents"

    var id: String
    var title: String
    var hostServerID: String

    static let defaultQuery = AgentQuery()

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

extension AgentEntity {
    init(entry: AgentDirectoryEntry) {
        // Display names follow the toggle at query time; the stored title stays
        // verbatim so flipping the toggle never loses data.
        let visible = showAgentNames ? entry.title : "Agent"
        self.init(id: entry.id, title: visible, hostServerID: entry.hostServerID)
    }
}
