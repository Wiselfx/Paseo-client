import Foundation

// MARK: - Glance mirror (Phase E G15)

// The extension's read-only view of `GlanceSnapshot` (PaseoStore). It mirrors the
// JSON shape field for field so the extension never links PaseoStore — Widget
// extensions have a tight memory ceiling, and the snapshot is plain data. Any
// field added to the source of truth must be added here. The App Group id is
// duplicated for the same reason; the source of truth is
// `GlanceSnapshot.appGroupID`.

/// Keep in sync with `GlanceSnapshot` (same property names, same JSON keys).
struct GlanceMirror: Codable {
    struct Agent: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var hostServerID: String
        var project: String?
        var provider: String?
        var status: String
        var requiresAttention: Bool
        var attentionReason: String?
        var activeTurnStartedAt: Date?
        var pendingPermissionCount: Int
        var updatedAt: Date?
    }

    var agents: [Agent]
    var runningCount: Int
    var capturedAt: Date
    var hostDisplayName: String?

    static let appGroupID = "group.com.wiselfx.paseoclient"
    static let fileName = "glance.json"

    /// The snapshot, or nil when the group is unavailable (no entitlement) or
    /// nothing was written yet. Synchronous and small; called from the timeline
    /// provider, never per frame.
    static func load() -> GlanceMirror? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID),
            let data = try? Data(
                contentsOf: container.appending(
                    path: fileName, directoryHint: .notDirectory)),
            let snapshot = try? JSONDecoder().decode(GlanceMirror.self, from: data)
        else { return nil }
        return snapshot
    }

    /// The agent deep link for a row, through the existing `paseo://` routes.
    static func deepLink(for agent: Agent) -> URL? {
        URL(string: "paseo://h/\(agent.hostServerID)/agent/\(agent.id)")
    }
}
