import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

// MARK: - Agent directory (Phase D G16)

// NOTE: The on-device agent index for intents and Spotlight. Intents and entity
// queries run without a host, so they read this persisted snapshot — never the
// network, never hang. Spotlight indexes agent TITLES ONLY (in-app search, the
// results never leave the phone); titles are private, so the index is purely local.
// Written when the agent list or attention changes (AppModel observes the session),
// off main; Spotlight updates diff by id so steady state costs nothing.

enum AgentDirectory {
    /// The persisted snapshot: Application Support survives cache evictions, so a
    /// relaunched app still resolves entities and Spotlight taps.
    static let fileURL = URL.applicationSupportDirectory
        .appending(path: "Paseo", directoryHint: .isDirectory)
        .appending(path: "agent-directory.json", directoryHint: .notDirectory)

    /// The snapshot, or empty when nothing was ever written. Small and synchronous;
    /// callers are already off the main path or one cheap read away from it.
    static func load() -> AgentDirectorySnapshot {
        guard let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(AgentDirectorySnapshot.self, from: data)
        else { return AgentDirectorySnapshot(agents: [], attentionIds: []) }
        return snapshot
    }

    /// Writes the snapshot and syncs Spotlight, off main. Coalesced by the caller:
    /// only changed projections reach here.
    static func publish(snapshot: AgentDirectorySnapshot) async {
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return
            }
            await syncSpotlight(agents: snapshot.agents)
        }.value
    }

    // MARK: Spotlight

    static let domainIdentifier = "paseo.agents"
    private static let indexedKey = "paseo.spotlight.indexedTitles"

    /// The Spotlight id for an agent: stable across title edits, so a rename
    /// re-indexes in place instead of duplicating.
    static func spotlightID(for agentID: String) -> String {
        "paseo-agent:\(agentID)"
    }

    /// Incremental: deletes ids that left, (re)indexes titles that arrived or
    /// changed. Titles only — no bodies, no paths, no keywords.
    static func syncSpotlight(agents: [AgentDirectoryEntry]) async {
        let current = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.title) })
        let previous =
            (UserDefaults.standard.dictionary(forKey: indexedKey) as? [String: String]) ?? [:]
        let removed = Set(previous.keys).subtracting(current.keys)
        // What gets recorded as indexed: a failed delete keeps its ids recorded, so the
        // next sync retries them instead of leaving them in Spotlight for good.
        var indexed = current
        if !removed.isEmpty {
            let ids = removed.map(spotlightID)
            do {
                try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids)
            } catch {
                for id in removed { indexed[id] = previous[id] }
            }
        }
        let changed = current.filter { previous[$0.key] != $0.value }
        if !changed.isEmpty {
            let items = changed.compactMap { id, title -> CSSearchableItem? in
                guard let entry = agents.first(where: { $0.id == id }) else { return nil }
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = entry.title
                return CSSearchableItem(
                    uniqueIdentifier: spotlightID(for: id),
                    domainIdentifier: domainIdentifier,
                    attributeSet: attributes)
            }
            do {
                try await CSSearchableIndex.default().indexSearchableItems(items)
            } catch {
                // Not recorded: the same titles are retried on the next sync.
                return
            }
        }
        UserDefaults.standard.set(indexed, forKey: indexedKey)
    }
}
