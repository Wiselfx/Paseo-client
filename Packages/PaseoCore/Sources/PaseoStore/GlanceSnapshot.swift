import Foundation
import PaseoProtocol

// MARK: - GlanceSnapshot (Phase E G14)

// NOTE: The App Group snapshot widgets and controls read. Per host it holds the
// agents (attention first), the running count, and the capture time. Titles arrive
// already redacted when "Show agent names" is off — the extension must never see
// a name the reader hid. Codable + Linux-tested; the app writes it, extensions
// only decode it (their own mirror struct keeps PaseoStore out of the extension).

/// What the home-screen widgets show: who needs you, what it will cost to look.
public struct GlanceSnapshot: Sendable, Equatable, Codable {
    public struct Agent: Sendable, Equatable, Hashable, Codable {
        public var id: String
        /// Already redacted when the reader hid names (`redactedTitle`).
        public var title: String
        /// The daemon server this agent belongs to: widgets deep-link with it.
        public var hostServerID: String
        public var project: String?
        public var provider: String?
        public var status: String
        public var requiresAttention: Bool
        public var attentionReason: String?
        public var activeTurnStartedAt: Date?
        public var pendingPermissionCount: Int
        public var updatedAt: Date?

        public init(
            id: String, title: String, hostServerID: String, project: String? = nil,
            provider: String? = nil, status: String, requiresAttention: Bool,
            attentionReason: String? = nil, activeTurnStartedAt: Date? = nil,
            pendingPermissionCount: Int, updatedAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.hostServerID = hostServerID
            self.project = project
            self.provider = provider
            self.status = status
            self.requiresAttention = requiresAttention
            self.attentionReason = attentionReason
            self.activeTurnStartedAt = activeTurnStartedAt
            self.pendingPermissionCount = pendingPermissionCount
            self.updatedAt = updatedAt
        }
    }

    /// Attention first, then the rest: the widget shows the head of this list.
    public var agents: [Agent]
    public var runningCount: Int
    public var capturedAt: Date
    /// The connected host's display name for the widget footer. Redacted with
    /// the titles when names are hidden.
    public var hostDisplayName: String?

    public init(
        agents: [Agent], runningCount: Int, capturedAt: Date,
        hostDisplayName: String? = nil
    ) {
        self.agents = agents
        self.runningCount = runningCount
        self.capturedAt = capturedAt
        self.hostDisplayName = hostDisplayName
    }

    /// The App Group container widgets read. Nil at runtime means no entitlement:
    /// the writer is a no-op.
    public static let appGroupID = "group.com.wiselfx.paseoclient"

    public static func fileURL(containerURL: URL?) -> URL? {
        containerURL?.appending(path: "glance.json", directoryHint: .notDirectory)
    }

    /// Titles are the user's prompts: when names are hidden the snapshot carries
    /// a generic label, never the real title.
    public static func redactedTitle(_ title: String?, showAgentNames: Bool) -> String {
        guard showAgentNames,
            let text = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return "Agent" }
        return text
    }

    /// Attention first, then most recently updated: what the widget shows on top.
    public static func sortAgents(_ agents: [Agent]) -> [Agent] {
        agents.sorted {
            if $0.requiresAttention != $1.requiresAttention { return $0.requiresAttention }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }
}
