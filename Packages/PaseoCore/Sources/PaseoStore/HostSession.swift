import Foundation
import Observation
import PaseoKit
import PaseoProtocol

/// Everything the UI knows about one connected daemon. Views read it; they never touch PaseoKit.
///
/// Owns the event loop: routes `agent_stream` deltas to open conversations, keeps the agent list
/// live from `agent_update`, and restores subscriptions and catches up after a reconnect.
///
/// IMPLEMENTATION TICKET: docs/tickets/T4-observable-store.md
@MainActor @Observable
public final class HostSession {
    public private(set) var connection: ConnectionState = .idle
    public private(set) var serverInfo: ServerInfo?
    /// Newest activity first (`updatedAt` descending). Archived agents are excluded.
    public private(set) var agents: [AgentSnapshot] = []
    /// Project placement by agent id, for grouping and titles.
    public private(set) var projects: [String: ProjectPlacement] = [:]
    /// Last error from loading the agent list, for display.
    public private(set) var agentsError: String?

    /// `client` should already be connected (the app calls `DaemonConnection.connect()` first,
    /// so it can show login errors before this exists).
    public init(client: any DaemonClient) { fatalError("T4: not implemented") }

    /// Starts the event and state loops, then loads the agent list with a live subscription.
    /// Call once. Safe to call while the connection is still settling.
    public func start() async { fatalError("T4: not implemented") }

    /// The store for one agent's conversation. Same instance for the same id while it is open.
    /// Opening subscribes the session to that agent's live stream.
    public func conversation(for agentId: String) -> ConversationStore { fatalError("T4: not implemented") }

    /// Call when the conversation screen goes away. Unsubscribes its stream; the store is dropped.
    public func closeConversation(_ agentId: String) { fatalError("T4: not implemented") }

    /// Re-fetches the agent list (pull to refresh).
    public func refreshAgents() async { fatalError("T4: not implemented") }
}

/// One agent's conversation: the rows, the turns built from them, and the actions on them.
///
/// IMPLEMENTATION TICKET: docs/tickets/T4-observable-store.md
@MainActor @Observable
public final class ConversationStore: Identifiable {
    public nonisolated let agentId: String
    public nonisolated var id: String { agentId }

    public enum LoadPhase: Sendable, Equatable {
        case loading
        case ready
        case failed(String)
    }

    public private(set) var phase: LoadPhase = .loading
    public private(set) var agent: AgentSnapshot?
    public private(set) var timeline = TimelineState()
    /// `TurnBuilder.turns(from: timeline.rows, activeTurnId: activeTurnId)`, kept in sync.
    public private(set) var turns: [Turn] = []
    /// The running turn. From the agent snapshot, made snappier by `turn_started`/`turn_completed`
    /// stream events.
    public private(set) var activeTurnId: String?
    public private(set) var isLoadingOlder = false
    /// Last failed send or cancel, for a transient error banner. Cleared by the next success.
    public private(set) var actionError: String?
    /// The composer text. Lives here so it survives navigating away and back.
    public var draft = ""

    /// True while the agent works: an active turn, or status `.running`.
    public var isRunning: Bool { fatalError("T4: not implemented") }

    init(agentId: String) {
        self.agentId = agentId
    }

    /// Loads the tail page. Called by `HostSession` when the conversation opens.
    public func load() async { fatalError("T4: not implemented") }

    /// Loads one page of older history. No-op while loading or when `!timeline.hasOlder`.
    public func loadOlder() async { fatalError("T4: not implemented") }

    /// Sends `text` (trimmed; no-op when empty). Shows it at once as a pending row, then sends
    /// `SendAgentMessageRequest` with a fresh `messageId`. If the agent is running, uses
    /// `activeTurnBehavior: "steer"`. Clears `draft` when `text == draft`.
    public func send(_ text: String) async { fatalError("T4: not implemented") }

    /// Stops the running turn (`CancelAgentRequest`).
    public func cancel() async { fatalError("T4: not implemented") }
}
