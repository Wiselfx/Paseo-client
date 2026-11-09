import Foundation
import Observation
import PaseoProtocol

/// Where a notification tap should go. Kept in PaseoCore so the app and the UI can pass it
/// without either importing the other. A terminal target names its workspace when known; an
/// agent target deliberately ignores any workspace hint (the agent can move after the event).
public struct AttentionTarget: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case agent
        case terminal
    }

    public let kind: Kind
    public let agentId: String?
    public let workspaceId: String?
    public let terminalId: String?

    public init(kind: Kind, agentId: String? = nil, workspaceId: String? = nil, terminalId: String? = nil) {
        self.kind = kind
        self.agentId = agentId
        self.workspaceId = workspaceId
        self.terminalId = terminalId
    }

    public static func agent(_ agentId: String, workspaceId: String? = nil) -> AttentionTarget {
        AttentionTarget(kind: .agent, agentId: agentId, workspaceId: workspaceId)
    }

    public static func terminal(_ terminalId: String, workspaceId: String? = nil) -> AttentionTarget {
        AttentionTarget(kind: .terminal, workspaceId: workspaceId, terminalId: terminalId)
    }

    /// The notification `userInfo` payload. Flat strings only: `UNNotificationContent.userInfo`
    /// is `[AnyHashable: Any]`, and flat keys survive a JSON round trip unchanged.
    public var userInfo: [String: String] {
        var info = ["kind": kind.rawValue]
        if let agentId, !agentId.isEmpty { info["agentId"] = agentId }
        if let workspaceId, !workspaceId.isEmpty { info["workspaceId"] = workspaceId }
        if let terminalId, !terminalId.isEmpty { info["terminalId"] = terminalId }
        return info
    }

    /// Rebuilds a target from notification `userInfo`. Returns nil when the payload names no
    /// destination (a notification from another client or an older build).
    public init?(userInfo: [String: String]) {
        guard let rawKind = userInfo["kind"], let kind = Kind(rawValue: rawKind) else { return nil }
        let agentId = Self.trimmed(userInfo["agentId"])
        let workspaceId = Self.trimmed(userInfo["workspaceId"])
        let terminalId = Self.trimmed(userInfo["terminalId"])
        switch kind {
        case .agent:
            guard let agentId else { return nil }
            self.init(kind: .agent, agentId: agentId, workspaceId: workspaceId)
        case .terminal:
            guard let terminalId else { return nil }
            self.init(kind: .terminal, workspaceId: workspaceId, terminalId: terminalId)
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// UserDefaults keys shared by the settings toggle (PaseoUI) and the poster (App).
public enum AttentionNotificationKeys {
    /// On by default. The OS permission prompt is separate and happens on first use.
    public static let enabled = "paseo.notifications.enabled"
}

/// One notification the app should post. Carries only plain values so the app layer never has
/// to reach back into a store to render it.
public struct AttentionIntent: Identifiable, Sendable, Equatable {
    /// Stable per destination: a newer event for the same agent/terminal replaces the older
    /// intent instead of stacking notifications.
    public let id: String
    public let target: AttentionTarget
    public let title: String
    public let body: String
    /// Wire reason (`finished`, `permission`, `needs_input`, …), for logs and diagnostics.
    public let reason: String?
    public let createdAt: Date

    public var agentId: String? { target.agentId }
    public var workspaceId: String? { target.workspaceId }
    public var terminalId: String? { target.terminalId }
}

/// Turns daemon attention events into deduped notification intents. Pure Foundation +
/// Observation so it is tested on Linux; the app decides whether to post them.
///
/// Rules, matching upstream (`notifyAgentAttention` in the reference app):
/// - pure `error` attention is never notified;
/// - an agent the user is currently looking at is suppressed locally as well as by the daemon;
/// - the daemon's `shouldNotify` is honoured (it already elected the right client);
/// - events older than or equal to the last one seen for a destination are dropped;
/// - terminal attention uses the daemon's own title/body and its `shouldNotify`.
///
/// IMPLEMENTATION TICKET: docs/tickets/M10-notifications.md
@MainActor @Observable
public final class AttentionCenter {
    /// Intents waiting for the app to post. Oldest first; one per destination.
    public private(set) var pending: [AttentionIntent] = []
    /// The agent the user is looking at, or nil while the app is backgrounded. The shell keeps
    /// this current from the scene phase and the selected conversation.
    public private(set) var focusedAgentId: String?

    /// Last attention timestamp accepted per intent id, for out-of-order and duplicate events.
    private var lastEventAt: [String: Date] = [:]

    public init() {}

    /// Updates the currently viewed agent. Pass nil when the app is not in the foreground (or
    /// no conversation is open).
    public func setFocusedAgent(_ agentId: String?) {
        focusedAgentId = agentId
    }

    /// Handles one agent attention event. Returns the queued intent, or nil when the event was
    /// suppressed as a pure error, as another client's notification, or as the focused agent.
    @discardableResult
    public func receive(
        agentId: String, workspaceId: String?, attention: AgentAttentionDetail
    ) -> AttentionIntent? {
        let intentId = "agent:\(agentId)"
        let eventAt = attention.timestamp.flatMap(PaseoDate.parse)
        if let eventAt, let last = lastEventAt[intentId], last >= eventAt { return nil }
        if let eventAt { lastEventAt[intentId] = eventAt }

        guard attention.reason != .error else { return nil }
        guard attention.shouldNotify else { return nil }
        guard focusedAgentId != agentId else { return nil }

        let resolvedWorkspace =
            attention.notification?.data?.workspaceId.flatMap(Self.nonEmpty) ?? workspaceId
        let fallback = Self.agentFallback(for: attention.reason)
        let title = Self.nonEmpty(attention.notification?.title) ?? fallback.title
        let body = Self.nonEmpty(attention.notification?.body) ?? fallback.body
        let intent = AttentionIntent(
            id: intentId,
            target: .agent(agentId, workspaceId: resolvedWorkspace),
            title: title,
            body: body,
            reason: attention.reason.rawValue,
            createdAt: eventAt ?? Date()
        )
        return enqueue(intent)
    }

    /// Handles one `terminal_attention_required` message. `workspaceId` is the caller's fallback
    /// when the daemon could not resolve one (it sends `cwd` in that case).
    @discardableResult
    public func receive(
        terminal: TerminalAttentionRequired, workspaceId: String? = nil
    ) -> AttentionIntent? {
        guard terminal.shouldNotify else { return nil }
        let resolvedWorkspace = terminal.workspaceId.flatMap(Self.nonEmpty) ?? workspaceId
        let intent = AttentionIntent(
            id: "terminal:\(terminal.terminalId)",
            target: .terminal(terminal.terminalId, workspaceId: resolvedWorkspace),
            title: Self.nonEmpty(terminal.title) ?? "Terminal needs attention",
            body: Self.nonEmpty(terminal.body) ?? "A terminal is waiting on you.",
            reason: Self.terminalReason(terminal.reason),
            createdAt: Date()
        )
        return enqueue(intent)
    }

    /// Removes and returns every queued intent. The app drains once per change and posts them.
    @discardableResult
    public func drain() -> [AttentionIntent] {
        let intents = pending
        pending.removeAll()
        return intents
    }

    /// Drops every queued intent without returning them (notifications turned off).
    public func clear() {
        pending.removeAll()
    }

    private func enqueue(_ intent: AttentionIntent) -> AttentionIntent {
        pending.removeAll { $0.id == intent.id }
        pending.append(intent)
        return intent
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func agentFallback(for reason: AgentAttentionReason) -> (title: String, body: String) {
        switch reason {
        case .permission:
            return ("Agent needs permission", "Permission requested.")
        case .error:
            return ("Agent needs attention", "Encountered an error.")
        case .finished, .unknown:
            return ("Agent finished", "Finished working.")
        }
    }

    private static func terminalReason(_ reason: TerminalAttentionReason) -> String {
        switch reason {
        case .finished: return "finished"
        case .needsInput: return "needs_input"
        case .unknown(let value): return value
        }
    }
}
