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

/// One row of the persisted snapshot: enough to open the agent and name it.
struct AgentDirectoryEntry: Codable, Sendable, Hashable {
    var id: String
    var title: String
    var hostServerID: String
}

/// The persisted snapshot: the agent list plus the ids currently needing attention.
struct AgentDirectorySnapshot: Codable, Sendable {
    var agents: [AgentDirectoryEntry]
    var attentionIds: [String]
}

enum AgentDirectory {
    /// The persisted snapshot: Application Support survives cache evictions, so a
    /// relaunched app still resolves entities and Spotlight taps.
    static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "Paseo", directoryHint: .isDirectory)
            .appending(path: "agent-directory.json", directoryHint: .notDirectory)
    }

    /// The snapshot, or empty when nothing was ever written. Small and synchronous;
    /// callers are already off the main path or one cheap read away from it.
    static func load() -> AgentDirectorySnapshot {
        guard let url = fileURL(),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(AgentDirectorySnapshot.self, from: data)
        else { return AgentDirectorySnapshot(agents: [], attentionIds: []) }
        return snapshot
    }

    /// Writes the snapshot and syncs Spotlight, off main. Coalesced by the caller:
    /// only changed projections reach here.
    static func publish(agents: [AgentDirectoryEntry], attentionIds: [String]) async {
        let snapshot = AgentDirectorySnapshot(agents: agents, attentionIds: attentionIds)
        await Task.detached(priority: .utility) {
            if let url = fileURL() {
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: url, options: .atomic)
                } catch {
                    return
                }
            }
            await syncSpotlight(agents: agents)
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
        if !removed.isEmpty {
            let ids = removed.map(spotlightID)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { _ in
                    continuation.resume()
                }
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
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                CSSearchableIndex.default().indexSearchableItems(items) { _ in
                    continuation.resume()
                }
            }
        }
        UserDefaults.standard.set(current, forKey: indexedKey)
    }
}
