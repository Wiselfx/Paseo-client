import Foundation

// Orchestration skills. The daemon owns edits through the `agent.skills.*` RPC family
// (get_status / reconcile / save_selection / uninstall / import_legacy_selection), which this
// client does not implement; the selection also rides the daemon config as a read-only field,
// so settings can show it without claiming it can edit it.
// Source: packages/protocol/src/agent-profile.ts `AgentSkillSelectionSchema`;
// `skills` key of messages.ts `MutableDaemonConfigSchema`.

/// How the host selects which orchestration skills agents get. Read-only client-side.
public enum AgentSkillSelection: Sendable, Hashable {
    /// Every skill the host has installed.
    case all
    /// Only these skill ids.
    case custom([String])

    /// One line for settings, e.g. "All skills" or "Custom (2 selected)".
    public var label: String {
        switch self {
        case .all: "All skills"
        case .custom(let ids): ids.count == 1 ? "Custom (1 selected)" : "Custom (\(ids.count) selected)"
        }
    }
}

extension DaemonConfig {
    /// Reads `skills.selection` from the raw config JSON. Returns `nil` when the host carries no
    /// selection (older daemons, or skills not configured) — callers hide the row then.
    public var skillsSelection: AgentSkillSelection? {
        guard case .object(let root)? = skills else { return nil }
        guard case .object(let selection)? = root["selection"] else { return nil }
        switch selection["mode"]?.stringValue {
        case "all": return .all
        case "custom":
            guard case .array(let items)? = selection["skills"] else { return .custom([]) }
            return .custom(items.compactMap(\.stringValue))
        default: return nil
        }
    }
}
