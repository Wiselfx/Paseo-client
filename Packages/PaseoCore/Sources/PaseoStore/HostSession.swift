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
    /// Live terminals and workspace scripts for every opened workspace.
    public let terminals: TerminalsStore
    /// Provider catalogue, agent creation, and live permission routing.
    public private(set) var agentControl: AgentControlStore

    private let client: any DaemonClient
    private var conversations: [String: ConversationStore] = [:]
    private var stateTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var isStarted = false
    /// True after a `.reconnecting` state; the next `.connected` must resync.
    private var sawReconnect = false

    /// `client` should already be connected (the app calls `DaemonConnection.connect()` first,
    /// so it can show login errors before this exists).
    public init(client: any DaemonClient) {
        self.client = client
        self.terminals = TerminalsStore(client: client)
        self.agentControl = AgentControlStore(client: client)
    }

    /// Starts the event and state loops, then loads the agent list with a live subscription.
    /// Call once. Safe to call while the connection is still settling.
    public func start() async {
        guard !isStarted else { return }
        isStarted = true

        let client = self.client
        stateTask = Task { [weak self] in
            for await state in client.states {
                guard let self else { return }
                await self.handle(state: state)
            }
        }
        eventTask = Task { [weak self] in
            for await event in client.events {
                guard let self else { return }
                await self.handle(event: event)
            }
        }

        await refreshAgents()
    }

    /// The store for one agent's conversation. Same instance for the same id while it is open.
    /// Opening subscribes the session to that agent's live stream.
    public func conversation(for agentId: String) -> ConversationStore {
        if let existing = conversations[agentId] { return existing }

        let store = ConversationStore(agentId: agentId, client: client)
        if let snapshot = agents.first(where: { $0.id == agentId }) {
            store.applyAgent(snapshot)
        }
        conversations[agentId] = store
        sendSubscription()

        Task { await store.load() }
        return store
    }

    /// Call when the conversation screen goes away. Unsubscribes its stream; the store is dropped.
    public func closeConversation(_ agentId: String) {
        guard conversations.removeValue(forKey: agentId) != nil else { return }
        sendSubscription()
    }

    /// Re-fetches the agent list (pull to refresh).
    public func refreshAgents() async {
        do {
            let response = try await client.send(FetchAgentsRequest(page: .init(limit: 200), subscribe: true))
            let entries = response.entries

            agents = entries
                .filter { $0.agent.archivedAt == nil }
                .map(\.agent)
                .sorted { isNewer($0, than: $1) }

            var placements: [String: ProjectPlacement] = [:]
            for entry in entries {
                if let project = entry.project { placements[entry.agent.id] = project }
            }
            projects = placements
            agentsError = nil
        } catch {
            agentsError = errorText(error)
        }
    }

    // MARK: State loop

    private func handle(state: ConnectionState) async {
        connection = state
        await terminals.handle(connection: state)
        switch state {
        case .connected(let info):
            serverInfo = info
            agentControl.serverInfoChanged(info)
            if sawReconnect {
                sawReconnect = false
                await resync()
            }
        case .reconnecting:
            sawReconnect = true
        case .idle, .connecting, .failed:
            break
        }
    }

    /// A reconnect means the daemon forgot our subscriptions and may have moved on without us.
    private func resync() async {
        sendSubscription()
        await refreshAgents()
        let stores = Array(conversations.values)
        for store in stores {
            await store.catchUp()
        }
    }

    // MARK: Event loop

    private func handle(event: DaemonEvent) async {
        switch event {
        case .agentStream(let payload):
            guard let store = conversations[payload.agentId] else { return }
            await store.handleStream(payload)

        case .agentUpdate(let update):
            apply(update)

        case .timelineReplacement(let agentId, _):
            guard let store = conversations[agentId] else { return }
            await store.reloadTail()

        case .unhandled(let messageType, let raw):
            terminals.handle(messageType: messageType, raw: raw)
            agentControl.handle(messageType: messageType, raw: raw, conversations: conversations)

        case .binaryFrame(let data):
            terminals.handle(binaryFrame: data)
        }
    }

    private func apply(_ update: AgentUpdate) {
        switch update {
        case .upsert(let agent, let project):
            if agent.archivedAt != nil {
                agents.removeAll { $0.id == agent.id }
                projects[agent.id] = nil
                return
            }
            if let index = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[index] = agent
            } else {
                agents.append(agent)
            }
            agents.sort { isNewer($0, than: $1) }
            if let project { projects[agent.id] = project }
            conversations[agent.id]?.applyAgent(agent)

        case .remove(let agentId):
            agents.removeAll { $0.id == agentId }
            projects[agentId] = nil

        case .unknown:
            break
        }
    }

    // MARK: Helpers

    /// Sends the complete set of open agent ids, replacing whatever the daemon held before.
    private func sendSubscription() {
        let agentIds = conversations.keys.sorted()
        let client = self.client
        Task {
            _ = try? await client.send(SetAgentTimelineSubscriptionRequest(agentIds: agentIds))
        }
    }

    private func isNewer(_ lhs: AgentSnapshot, than rhs: AgentSnapshot) -> Bool {
        let left = PaseoDate.parse(lhs.updatedAt)
        let right = PaseoDate.parse(rhs.updatedAt)
        switch (left, right) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.id < rhs.id
        }
    }
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
    /// Pending permission requests, oldest first. Seeded from the agent snapshot and kept live by
    /// `agent_permission_request`/`agent_permission_resolved` (and the stream's permission events).
    public private(set) var pendingPermissions: [AgentPermissionRequest] = []
    /// The provider's notice from the last accepted change, e.g. "applies next turn". Render as a
    /// toast; `clearNotice()` once shown.
    public private(set) var lastNotice: AgentProviderNotice?
    /// Last failed send, cancel or agent change, for a transient error banner. Cleared by the next success.
    public private(set) var actionError: String?
    /// The composer text. Lives here so it survives navigating away and back.
    public var draft = ""

    private let client: (any DaemonClient)?
    private var isCatchingUp = false

    /// True while the agent works: an active turn, or status `.running`.
    public var isRunning: Bool { activeTurnId != nil || agent?.status == .running }

    init(agentId: String) {
        self.agentId = agentId
        self.client = nil
    }

    internal init(agentId: String, client: any DaemonClient) {
        self.agentId = agentId
        self.client = client
    }

    /// Loads the tail page. Called by `HostSession` when the conversation opens.
    public func load() async {
        guard let client else { return }
        do {
            let page = try await client.send(
                FetchAgentTimelineRequest(agentId: agentId, direction: .tail, limit: 40))
            timeline.applyPage(page)
            if let snapshot = page.agent { applyAgent(snapshot) }
            updateTurns()
            phase = .ready
            // Opening a conversation is deliberate focus: acknowledge attention on the daemon.
            if agent?.requiresAttention == true { await clearAttention() }
        } catch {
            if timeline.rows.isEmpty {
                phase = .failed(errorText(error))
            } else {
                actionError = errorText(error)
            }
        }
    }

    /// Loads one page of older history. No-op while loading or when `!timeline.hasOlder`.
    public func loadOlder() async {
        guard !isLoadingOlder, timeline.hasOlder, let cursor = timeline.startCursor, let client else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await client.send(
                FetchAgentTimelineRequest(agentId: agentId, direction: .before, cursor: cursor, limit: 40))
            timeline.applyPage(page)
            if let snapshot = page.agent { applyAgent(snapshot) }
            updateTurns()
        } catch {
            actionError = errorText(error)
        }
    }

    /// Sends `text` (trimmed; no-op when empty). Shows it at once as a pending row, then sends
    /// `SendAgentMessageRequest` with a fresh `messageId`. If the agent is running, uses
    /// `activeTurnBehavior: "steer"`. Clears `draft` when `text == draft`.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let client else { return }

        let clientId = UUID().uuidString
        timeline.addPendingUserMessage(text: trimmed, clientMessageId: clientId, timestamp: Self.nowTimestamp())
        updateTurns()
        if trimmed == draft.trimmingCharacters(in: .whitespacesAndNewlines) {
            draft = ""
        }

        do {
            let response = try await client.send(
                SendAgentMessageRequest(
                    agentId: agentId,
                    text: trimmed,
                    messageId: clientId,
                    activeTurnBehavior: isRunning ? "steer" : nil))
            if response.accepted {
                actionError = nil
            } else {
                rollBackSend(clientId: clientId, text: trimmed, error: response.error ?? "The daemon rejected the message.")
            }
        } catch {
            rollBackSend(clientId: clientId, text: trimmed, error: errorText(error))
        }
    }

    /// Stops the running turn (`CancelAgentRequest`).
    public func cancel() async {
        guard let client else { return }
        do {
            let response = try await client.send(CancelAgentRequest(agentId: agentId))
            if let error = response.error {
                actionError = error
            } else {
                actionError = nil
            }
        } catch {
            actionError = errorText(error)
        }
    }

    // MARK: Permissions

    /// Answers one pending request. The card disappears when the daemon reports the resolution
    /// (`agent_permission_resolved`), not optimistically, so a rejected answer keeps it visible.
    public func respond(to requestId: String, with response: AgentPermissionResponse) async {
        guard let client else { return }
        client.sendExpectingEvent(
            RespondToAgentPermissionRequest(
                agentId: agentId, permissionRequestId: requestId, response: response))
    }

    // MARK: Agent settings

    /// Switches the agent's approval mode. A provider may stage the change for the next turn and
    /// say so in `lastNotice`.
    public func setMode(_ modeId: String) async {
        await perform(SetAgentModeRequest(agentId: agentId, modeId: modeId), change: .mode(modeId))
    }

    /// Sets, or with `nil` clears, the model override.
    public func setModel(_ modelId: String?) async {
        await perform(SetAgentModelRequest(agentId: agentId, modelId: modelId), change: .model(modelId))
    }

    /// Sets, or with `nil` clears, the thinking level.
    public func setThinking(_ thinkingOptionId: String?) async {
        await perform(
            SetAgentThinkingRequest(agentId: agentId, thinkingOptionId: thinkingOptionId),
            change: .thinking(thinkingOptionId))
    }

    /// Renames the agent. Empty or whitespace-only names are ignored.
    public func rename(to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await perform(UpdateAgentRequest(agentId: agentId, name: trimmed), change: .rename(trimmed))
    }

    /// Archives (soft-deletes) the agent. `HostSession` drops it from the list on the resulting
    /// `agent_update`.
    public func archive() async {
        guard let client else { return }
        do {
            let response = try await client.send(ArchiveAgentRequest(agentId: agentId))
            agent?.archivedAt = response.archivedAt
            actionError = nil
        } catch {
            actionError = errorText(error)
        }
    }

    /// Clears the unread badge on the daemon. Failures are ignored: attention is advisory and a
    /// stale badge must never block opening a conversation.
    public func clearAttention() async {
        guard let client else { return }
        guard let response = try? await client.send(ClearAgentAttentionRequest(agentId: agentId)) else {
            return
        }
        if let snapshot = response.agents.first(where: { $0.id == agentId }) {
            applyAgent(snapshot)
        } else if var snapshot = agent {
            snapshot.requiresAttention = false
            snapshot.attentionReason = nil
            agent = snapshot
        }
    }

    /// Dismisses `lastNotice` once the UI has shown it.
    public func clearNotice() { lastNotice = nil }

    // MARK: HostSession handoff

    /// Takes an agent snapshot from `HostSession` and follows its running turn.
    internal func applyAgent(_ snapshot: AgentSnapshot) {
        agent = snapshot
        pendingPermissions = snapshot.permissionRequests
        setActiveTurn(snapshot.activeTurn?.turnId)
    }

    /// Adds a live permission request unless it is already showing.
    internal func addPermission(_ request: AgentPermissionRequest) {
        guard !pendingPermissions.contains(where: { $0.id == request.id }) else { return }
        pendingPermissions.append(request)
    }

    /// Removes a resolved request, whoever answered it.
    internal func removePermission(requestId: String) {
        pendingPermissions.removeAll { $0.id == requestId }
    }

    /// Applies one live `agent_stream` payload routed by `HostSession`.
    internal func handleStream(_ payload: AgentStreamPayload) async {
        guard payload.agentId == agentId else { return }
        switch payload.event {
        case .turnStarted(let turnId):
            setActiveTurn(turnId)

        case .turnCompleted, .turnFailed, .turnCanceled:
            setActiveTurn(nil)

        case .permissionRequested(let raw):
            if let request = try? raw.decoded(as: AgentPermissionRequest.self) {
                addPermission(request)
            }

        case .permissionResolved(let requestId):
            removePermission(requestId: requestId)

        case .timeline:
            switch timeline.applyStream(payload) {
            case .applied:
                updateTurns()
            case .gap:
                await catchUp()
            case .epochChanged:
                await load()
            case .duplicate, .ignored:
                break
            }

        default:
            break
        }
    }

    /// The daemon rebuilt this timeline: drop local rows and fetch the tail again.
    internal func reloadTail() async {
        timeline = TimelineState()
        updateTurns()
        await load()
    }

    /// Fetches everything after the last known seq. Repeats while the daemon reports newer rows.
    internal func catchUp() async {
        guard !isCatchingUp, let client else { return }
        isCatchingUp = true
        defer { isCatchingUp = false }

        guard var cursor = timeline.endCursor else {
            await load()
            return
        }

        while true {
            do {
                let page = try await client.send(
                    FetchAgentTimelineRequest(agentId: agentId, direction: .after, cursor: cursor, limit: 0))
                timeline.applyPage(page)
                if let snapshot = page.agent { applyAgent(snapshot) }
                updateTurns()
                guard page.hasNewer else { return }
                guard let next = timeline.endCursor, next != cursor else { return }
                cursor = next
            } catch {
                actionError = errorText(error)
                return
            }
        }
    }

    // MARK: Internals

    private enum AgentChange {
        case mode(String)
        case model(String?)
        case thinking(String?)
        case rename(String)
    }

    private func perform<R: PaseoRequest>(_ request: R, change: AgentChange) async
    where R.Response == AgentActionResponse {
        guard let client else { return }
        do {
            let response = try await client.send(request)
            if let error = response.error {
                actionError = error
                return
            }
            guard response.accepted else {
                actionError = "The daemon rejected the change."
                return
            }
            actionError = nil
            lastNotice = response.notice
            guard var snapshot = agent else { return }
            switch change {
            case .mode(let modeId):
                snapshot.currentModeId = modeId
            case .model(let modelId):
                snapshot.model = modelId
            case .thinking(let optionId):
                snapshot.thinkingOptionId = optionId
                snapshot.effectiveThinkingOptionId = optionId
            case .rename(let title):
                snapshot.title = title
            }
            agent = snapshot
        } catch {
            actionError = errorText(error)
        }
    }

    private func rollBackSend(clientId: String, text: String, error: String) {
        timeline.removePendingUserMessage(clientMessageId: clientId)
        updateTurns()
        if draft.isEmpty { draft = text }
        actionError = error
    }

    private func setActiveTurn(_ turnId: String?) {
        guard activeTurnId != turnId else { return }
        activeTurnId = turnId
        updateTurns()
    }

    private func updateTurns() {
        turns = TurnBuilder.turns(from: timeline.rows, activeTurnId: activeTurnId)
    }

    private static func nowTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

/// One readable line for an error, for `agentsError` / `actionError`.
private func errorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
