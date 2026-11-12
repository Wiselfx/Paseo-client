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
    /// Agents with status `.running`. Maintained on every `agents` change, so views observe one
    /// number instead of scanning the list.
    public private(set) var runningAgentCount = 0
    /// The daemon-confirmed permission answers for this agent (card taps and
    /// notification actions alike). Rendered only after confirmation (D8).
    public internal(set) var permissionResolvedLines: [AnsweredPermission] = []
    /// Sum of `pendingPermissions.count` over `agents`.
    public private(set) var pendingPermissionCount = 0
    /// Agents with `requiresAttention == true`.
    public private(set) var attentionCount = 0
    /// Project placement by agent id, for grouping and titles.
    public private(set) var projects: [String: ProjectPlacement] = [:]
    /// The sidebar's live project/workspace directory.
    public private(set) var workspaceDirectory: WorkspaceDirectory
    /// Last error from loading the agent list, for display.
    public private(set) var agentsError: String?
    /// Provider plan usage reports for this host (e.g. Claude/Copilot windows).
    public let hostUsage: HostUsageStore
    /// Live terminals and workspace scripts for every opened workspace.
    public let terminals: TerminalsStore
    /// Provider catalogue, agent creation, and live permission routing.
    public private(set) var agentControl: AgentControlStore
    /// Schedules and heartbeats. No live push: the schedules screen calls `load()`.
    public let schedules: SchedulesStore
    /// Host config, presence, slash commands and push registration for this daemon.
    public private(set) var hostSettings: HostSettingsStore
    /// Host Voice settings + local speech models (M13). Reads/writes through hostSettings.
    public let voiceSettings: VoiceSettingsStore
    /// Realtime voice mode transport + playback state machine (M15).
    public let voiceSession: VoiceModeSession
    /// Worktree setup observation (running/failed/blocked snapshot per workspace).
    public let setupObservation: WorkspaceSetupObservationStore
    /// Socket-wide event subscription for pushes the other subscriptions don't carry
    /// (provider snapshots, permissions, script status, subagent and background-work updates).
    public let ownedEvents: OwnedEventSubscription
    /// Project `paseo.json` read/write + project icons (Settings → host → Projects → Project).
    public let projectConfig: ProjectConfigStore
    public let projectIcons: ProjectIconStore
    /// Shared T14 upload channel for "paste a file into the terminal" (progress observable, one
    /// upload at a time). Per-conversation uploads are separate instances on each ConversationStore.
    public let fileUploader: ConversationUpload
    /// Git extras for open workspaces: modern diffs, discard, branches, PR badge, live files.
    public let gitExtras: GitExtrasStore
    /// History and lifecycle: archived agents, archive/unarchive/delete.
    public let agentLifecycle: AgentLifecycleStore
    /// Deduped notification intents from agent and terminal attention events (M10).
    public let attention: AttentionCenter
    /// The label catalog for this host (name + color). Assignments live on the workspace rows.
    public let labels: WorkspaceLabelsStore
    /// M2.13: lazy worktree-setup probe powering the sidebar's "Set up worktree scripts" callout.
    public let projectSetupProbe: ProjectSetupProbe
    /// Recent provider sessions and importing one into a Paseo agent (M11).
    public let importSession: ImportSessionStore
    /// Forge issue/PR search for the composer's attach picker (M12).
    public let forgeSearch: ForgeSearchStore

    private let client: any DaemonClient
    /// Whether the daemon is reached through the relay (G2 §12): relay traffic is slow and
    /// metered, so large media waits for a tap. The same endpoint flag the upload chunking
    /// (R18) already keys off.
    public var isRelayConnection: Bool {
        (client as? DaemonConnection)?.endpoint.relay != nil
    }
    private var conversations: [String: ConversationStore] = [:]
    /// Parsed `updatedAt` per agent id, kept in step with `agents`, so the sort comparator and the
    /// binary-search insertion never parse a date string.
    private var agentDates: [String: Date?] = [:]
    /// Per-agent live-delta coalescers, keyed like `conversations`. A `.timeline` payload is
    /// buffered here and committed once per display frame instead of on every delta.
    private var timelineCoalescers: [String: TimelineCommitCoalescer] = [:]
    private var checkouts: [String: CheckoutStore] = [:]
    /// The agent-list subscription, so a re-fetch can release the previous one on a modern socket.
    private var agentsSubscriptionId: String?
    /// The timeline subscription, so a changed viewed set can release the previous one.
    private var timelineSubscriptionId: String?
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
        self.hostUsage = HostUsageStore(client: client)
        self.agentControl = AgentControlStore(client: client)
        self.schedules = SchedulesStore(client: client)
        let hostSettings = HostSettingsStore(client: client)
        self.hostSettings = hostSettings
        self.workspaceDirectory = WorkspaceDirectory(client: client)
        self.gitExtras = GitExtrasStore(client: client)
        self.setupObservation = WorkspaceSetupObservationStore(client: client)
        self.ownedEvents = OwnedEventSubscription(client: client)
        self.projectConfig = ProjectConfigStore(client: client)
        self.projectIcons = ProjectIconStore(client: client)
        self.agentLifecycle = AgentLifecycleStore(client: client)
        self.attention = AttentionCenter()
        self.labels = WorkspaceLabelsStore(client: client)
        self.fileUploader = ConversationUpload(client: client)
        self.fileUploader.isRelayConnection = (client as? DaemonConnection)?.endpoint.relay != nil
        self.projectSetupProbe = ProjectSetupProbe(client: client)
        self.importSession = ImportSessionStore(client: client)
        self.forgeSearch = ForgeSearchStore(client: client)
        self.voiceSettings = VoiceSettingsStore(client: client, hostSettings: hostSettings)
        self.voiceSession = VoiceModeSession(client: client)
        self.labels.workspaceDirectory = self.workspaceDirectory
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
        store.update(serverInfo: serverInfo)
        conversations[agentId] = store
        timelineCoalescers[agentId] = TimelineCommitCoalescer(store: store)
        sendSubscription()

        Task { await store.load() }
        return store
    }

    /// The checkout store for one open workspace. Same instance for the same id while it is open.
    /// Creating it loads git status, the PR badge and the working diff.
    public func checkout(for workspace: WorkspaceDescriptor) -> CheckoutStore {
        if let existing = checkouts[workspace.id] {
            existing.update(workspace: workspace)
            return existing
        }
        let store = CheckoutStore(workspace: workspace, client: client)
        store.update(serverInfo: serverInfo)
        checkouts[workspace.id] = store
        Task { await store.load() }
        return store
    }

    /// The checkout store for a workspace if one is already open, without creating or loading one.
    /// Safe to call while a view is drawing.
    public func existingCheckout(_ workspaceId: String) -> CheckoutStore? {
        checkouts[workspaceId]
    }

    /// Call when the checkout screen goes away. Releases its diff subscription.
    public func closeCheckout(_ workspaceId: String) async {
        await gitExtras.close(workspaceId)
        guard let store = checkouts.removeValue(forKey: workspaceId) else { return }
        await store.close()
    }

    /// Call when the conversation screen goes away. Unsubscribes its stream; the store is dropped.
    public func closeConversation(_ agentId: String) {
        timelineCoalescers.removeValue(forKey: agentId)
        guard conversations.removeValue(forKey: agentId) != nil else { return }
        sendSubscription()
    }

    /// Re-fetches the agent list (pull to refresh).
    ///
    /// Pages to the end the way upstream's directory sync does
    /// (`directory-sync/index.ts:701-745`): `scope: "active"` so archived rows cannot crowd
    /// active ones off a page, newest first, `subscribe` on the first page only, and the next
    /// cursor followed while the host says there is one.
    public func refreshAgents() async {
        var entries: [FetchAgentsRequest.Response.Entry] = []
        var firstPageSubscriptionId: String?
        var cursor: String?
        var seenCursors: Set<String> = []
        // Gated the way upstream gates it: only a host with background workspaces is asked for
        // their agents, so an older daemon never sees the field.
        let includeBackground = serverInfo?.hasFeature("backgroundWorkspaces") == true
        do {
            while true {
                let page = FetchAgentsRequest.Page(
                    limit: FetchAgentsRequest.maxPageLimit, cursor: cursor)
                let response = try await client.send(
                    FetchAgentsRequest(
                        page: page,
                        subscribe: cursor == nil,
                        scope: "active",
                        includeBackground: includeBackground ? true : nil,
                        sort: [.updatedAtDescending]))
                if cursor == nil { firstPageSubscriptionId = response.subscriptionId }
                entries.append(contentsOf: response.entries)
                // A host that answers with no page info, no next cursor, a cursor we already
                // read, or a cursor with `hasMore` false has no further page.
                guard let next = response.pageInfo?.cursorForNextPage,
                    seenCursors.insert(next).inserted
                else { break }
                cursor = next
            }
            guard !Task.isCancelled else { return }

            let previousSubscriptionId = agentsSubscriptionId
            agentsSubscriptionId = firstPageSubscriptionId
            // A modern socket creates a new owned subscription per subscribe; an old one would
            // keep delivering the same agent updates. Release it after the new snapshot lands.
            if serverInfo?.supportsOwnedSubscriptions == true, let previousSubscriptionId,
                previousSubscriptionId != agentsSubscriptionId
            {
                await client.releaseOwnedSubscription(previousSubscriptionId)
            }

            // `scope: "active"` already excludes archived rows on a modern host; the filter keeps
            // an old host's list honest.
            setAgents(sortedAgents(entries.filter { $0.agent.archivedAt == nil }.map(\.agent)))

            var placements: [String: ProjectPlacement] = [:]
            for entry in entries {
                if let project = entry.project { placements[entry.agent.id] = project }
            }
            projects = placements
            agentsError = nil
        } catch {
            agentsError = errorText(error)
            // The subscribe we just opened will never be used; the previous one stays live.
            if let firstPageSubscriptionId, firstPageSubscriptionId != agentsSubscriptionId,
                serverInfo?.supportsOwnedSubscriptions == true
            {
                await client.releaseOwnedSubscription(firstPageSubscriptionId)
            }
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
            schedules.serverInfoChanged(info)
            hostSettings.serverInfoChanged(info)
            voiceSettings.serverInfoChanged(info)
            voiceSession.serverInfoChanged(info)
            importSession.serverInfoChanged(info)
            forgeSearch.serverInfoChanged(info)
            hostUsage.update(serverInfo: info)
            workspaceDirectory.update(serverInfo: info)
            setupObservation.update(serverInfo: info)
            projectIcons.update(serverInfo: info)
            gitExtras.update(serverInfo: info)
            labels.update(serverInfo: info)
            ownedEvents.update(serverInfo: info)
            for store in checkouts.values { store.update(serverInfo: info) }
            for store in conversations.values { store.update(serverInfo: info) }
            // The daemon drops every subscription with the previous socket: always re-subscribe.
            // Advisory only, so it never delays the directory, labels or a resync.
            Task { await ownedEvents.connected() }
            Task { await voiceSession.handle(connection: state) }
            if sawReconnect {
                sawReconnect = false
                await resync()
            } else {
                await workspaceDirectory.reload()
                await labels.load()
            }
        case .reconnecting:
            sawReconnect = true
            ownedEvents.disconnected()
            voiceSettings.stopModelPolling()
            await voiceSession.handle(connection: state)
            agentsSubscriptionId = nil
            timelineSubscriptionId = nil
        case .idle, .connecting:
            ownedEvents.disconnected()
            voiceSettings.stopModelPolling()
            await voiceSession.handle(connection: state)
            agentsSubscriptionId = nil
            timelineSubscriptionId = nil
        case .failed:
            ownedEvents.disconnected()
            voiceSettings.stopModelPolling()
            await voiceSession.handle(connection: state)
            agentsSubscriptionId = nil
            timelineSubscriptionId = nil
        }
    }

    /// A reconnect means the daemon forgot our subscriptions and may have moved on without us.
    private func resync() async {
        sendSubscription()
        await refreshAgents()
        let stores = Array(conversations.values)
        for store in stores {
            await store.catchUp()
            await store.reloadSubagents()
            await store.reloadBackgroundWork()
        }
        workspaceDirectory.prepareForReconnect()
        await workspaceDirectory.reload()
        labels.prepareForReconnect()
        await labels.load()
        await setupObservation.resubscribe()
        let openCheckouts = Array(checkouts.values)
        for store in openCheckouts {
            await store.resubscribe()
        }
        await gitExtras.resubscribe()
    }

    // MARK: Event loop

    private func handle(event: DaemonEvent) async {
        switch event {
        case .agentStream(let payload):
            // Legacy daemons deliver attention as an `attention_required` stream event, with the
            // per-client notification plan attached to the event. Capture it even when no
            // conversation for this agent is open — that is the whole point of a notification.
            if let attention = payload.attention {
                let workspaceId = agents.first { $0.id == payload.agentId }?.workspaceId
                self.attention.receive(
                    agentId: payload.agentId, workspaceId: workspaceId, attention: attention)
            }
            voiceSession.handle(agentStream: payload)
            guard let store = conversations[payload.agentId] else { return }
            if case .timeline = payload.event {
                // Coalesced: consecutive deltas are merged and committed once per display
                // frame. Non-timeline events (turn lifecycle, permissions, usage) are
                // stateful and always applied immediately.
                timelineCoalescers[payload.agentId]?.enqueue(payload)
            } else {
                // A lifecycle event is a barrier: commit buffered deltas first so the turn's
                // final text is in place before the turn completes or a permission appears.
                timelineCoalescers[payload.agentId]?.flush()
                await store.handleStream(payload)
            }

        case .agentUpdate(let update):
            apply(update)

        case .timelineReplacement(let agentId, _):
            guard let store = conversations[agentId] else { return }
            await store.reloadTail()

        case .unhandled(let messageType, let raw):
            terminals.handle(messageType: messageType, raw: raw)
            agentControl.handle(messageType: messageType, raw: raw, conversations: conversations)
            hostSettings.handle(messageType: messageType, raw: raw)
            setupObservation.handle(messageType: messageType, raw: raw)
            handleConversationUpdate(messageType: messageType, raw: raw)
            await handleUnhandled(messageType: messageType, raw: raw)

        case .binaryFrame(let data):
            terminals.handle(binaryFrame: data)
            gitExtras.handle(binaryFrame: data)
        }
    }

    /// One shared decoder per pushed payload type. `JSONDecoder` is safe for repeated sequential
    /// use on the main actor, and decoding once here is what stops every open conversation from
    /// decoding the same bytes again.
    private static let subagentUpdateDecoder = JSONDecoder()
    private static let backgroundWorkUpdateDecoder = JSONDecoder()

    /// `agent.provider_subagents.update` and `agent.background_work.update` name their parent
    /// agent, so they are decoded once and handed to that conversation only. A payload with no
    /// parent id falls back to offering it to every open conversation, as before.
    private func handleConversationUpdate(messageType: String, raw: Data) {
        switch messageType {
        case ConversationSubagents.messageType:
            guard
                let update = try? Self.subagentUpdateDecoder.decode(
                    SessionPayloadEnvelope<ProviderSubagentUpdate>.self, from: raw
                ).payload
            else { return }
            guard let parentAgentId = Self.parentAgentId(of: update) else {
                for store in conversations.values {
                    store.handleSubagentUpdate(messageType: messageType, raw: raw)
                }
                return
            }
            conversations[parentAgentId]?.handleSubagentUpdate(update)

        case BackgroundWorkStore.messageType:
            guard
                let update = try? Self.backgroundWorkUpdateDecoder.decode(
                    SessionPayloadEnvelope<BackgroundWorkUpdate>.self, from: raw
                ).payload
            else { return }
            guard !update.agentId.isEmpty else {
                for store in conversations.values {
                    store.handleBackgroundWorkUpdate(messageType: messageType, raw: raw)
                }
                return
            }
            conversations[update.agentId]?.handleBackgroundWorkUpdate(update)

        default:
            break
        }
    }

    /// The parent agent a pushed subagent update belongs to, or nil when the payload names none.
    private static func parentAgentId(of update: ProviderSubagentUpdate) -> String? {
        switch update.kind {
        case .upsert(let subagent):
            return subagent.parentAgentId
        case .remove(let removal):
            return removal.parentAgentId
        case .timeline(let timeline):
            return timeline.parentAgentId
        case .unknown:
            return nil
        }
    }

    /// Newer daemon message types this ticket owns. Decoded here, from `raw`, so PaseoKit's
    /// `DaemonEvent` stays small.
    private func handleUnhandled(messageType: String, raw: Data) async {
        let decoder = JSONDecoder()
        hostUsage.handle(messageType: messageType, raw: raw)
        gitExtras.handle(messageType: messageType, raw: raw)
        switch messageType {
        case "workspace.label.update":
            if let update = try? decoder.decode(SessionPayloadEnvelope<WorkspaceLabelUpdate>.self, from: raw)
                .payload
            {
                labels.handle(update)
                await labels.resyncIfNeeded()
            }
        case "workspace_update":
            if let update = try? decoder.decode(SessionPayloadEnvelope<WorkspaceUpdate>.self, from: raw).payload {
                workspaceDirectory.apply(update)
            }
        case "project.update":
            if let update = try? decoder.decode(SessionPayloadEnvelope<ProjectUpdate>.self, from: raw).payload {
                workspaceDirectory.apply(update)
            }
        case "checkout_status_update":
            if let update = try? decoder.decode(SessionPayloadEnvelope<CheckoutStatusUpdate>.self, from: raw)
                .payload
            {
                workspaceDirectory.apply(status: update.status)
                for store in checkouts.values { store.handle(update) }
            }
        case "checkout_diff_update":
            if let update = try? decoder.decode(SessionPayloadEnvelope<CheckoutDiff>.self, from: raw).payload {
                for store in checkouts.values { store.handle(update) }
            }
        case "agent_attention_required":
            // A modern socket never receives the attention frame inside `agent_stream`
            // (`session.ts:1457-1463` skips it), so this message is the only delivery. It names
            // no workspace: resolve it from the agent snapshot, which the agents subscription keeps
            // current even with no conversation open.
            if let payload = try? decoder.decode(
                SessionPayloadEnvelope<AgentAttentionRequired>.self, from: raw
            ).payload {
                attention.receive(
                    agentId: payload.agentId,
                    workspaceId: agents.first { $0.id == payload.agentId }?.workspaceId,
                    attention: AgentAttentionDetail(
                        reason: payload.reason,
                        timestamp: payload.timestamp,
                        shouldNotify: payload.shouldNotify,
                        notification: payload.notification))
            }
        case "terminal_attention_required":
            if let payload = try? decoder.decode(
                SessionPayloadEnvelope<TerminalAttentionRequired>.self, from: raw
            ).payload {
                attention.receive(
                    terminal: payload,
                    workspaceId: payload.workspaceId
                        ?? terminals.workspaceId(forTerminal: payload.terminalId))
            }
        case "audio_output":
            if let payload = try? decoder.decode(
                SessionPayloadEnvelope<AudioOutputPayload>.self, from: raw
            ).payload {
                voiceSession.handleAudioOutput(payload)
            }
        case "transcription_result":
            if let payload = try? decoder.decode(
                SessionPayloadEnvelope<TranscriptionResultPayload>.self, from: raw
            ).payload {
                voiceSession.handleTranscription(payload)
            }
        case "voice_input_state":
            if let payload = try? decoder.decode(
                SessionPayloadEnvelope<VoiceInputStatePayload>.self, from: raw
            ).payload {
                voiceSession.handleVoiceInputState(payload)
            }
        default:
            break
        }
    }

    private func apply(_ update: AgentUpdate) {
        switch update {
        case .upsert(let agent, let project):
            if let project { projects[agent.id] = project }
            if agent.archivedAt != nil {
                removeAgent(agent.id)
                return
            }
            let date = PaseoDate.parse(agent.updatedAt)
            if let index = agents.firstIndex(where: { $0.id == agent.id }) {
                // An identical snapshot is the common case for a live socket chattering about an
                // agent that did not change. Assigning `agents` would notify every observer, so
                // return before touching it. The open conversation already holds this snapshot.
                if agents[index] == agent { return }
                agents.remove(at: index)
            }
            // Re-insert only this agent, in its place in the existing order. No full sort.
            agentDates[agent.id] = date
            agents.insert(agent, at: insertionIndex(for: agent, updatedAt: date))
            refreshAgentCounts()
            conversations[agent.id]?.applyAgent(agent)

        case .remove(let agentId):
            removeAgent(agentId)

        case .unknown:
            break
        }
    }

    /// Drops one agent (an `agent_update` removal or an archive) and keeps the counts in step.
    private func removeAgent(_ agentId: String) {
        projects[agentId] = nil
        agentDates[agentId] = nil
        guard agents.contains(where: { $0.id == agentId }) else { return }
        agents.removeAll { $0.id == agentId }
        refreshAgentCounts()
    }

    /// Recomputes the aggregate counters in one pass over `agents`.
    private func refreshAgentCounts() {
        var running = 0
        var permissions = 0
        var attention = 0
        for agent in agents {
            if agent.status == .running { running += 1 }
            permissions += agent.pendingPermissions.count
            if agent.requiresAttention == true { attention += 1 }
        }
        if runningAgentCount != running { runningAgentCount = running }
        if pendingPermissionCount != permissions { pendingPermissionCount = permissions }
        if attentionCount != attention { attentionCount = attention }
    }

    /// The index `agent` takes in `agents` (which is sorted and does not contain it): binary search
    /// with the same comparator as a full sort. `agentDates` holds every cached date, so the search
    /// never parses.
    private func insertionIndex(for agent: AgentSnapshot, updatedAt date: Date?) -> Int {
        var low = 0
        var high = agents.count
        while low < high {
            let mid = (low + high) / 2
            let other = agents[mid]
            if isNewer(agent, date, than: other, agentDates[other.id] ?? nil) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }

    // MARK: Helpers

    /// Sends the complete set of open agent ids, replacing whatever the daemon held before.
    private func sendSubscription() {
        let agentIds = conversations.keys.sorted()
        let client = self.client
        Task {
            guard let response = try? await client.send(
                SetAgentTimelineSubscriptionRequest(agentIds: agentIds)) else { return }
            let replaced = timelineSubscriptionId
            timelineSubscriptionId = response.subscriptionId
            // A modern socket keeps the previous subscription alive until it is released, and
            // each subscription delivers its own copy of every stream. Release the old one
            // after the new snapshot lands so nothing is missed and nothing is duplicated.
            if serverInfo?.supportsOwnedSubscriptions == true, let replaced,
                replaced != timelineSubscriptionId
            {
                await client.releaseOwnedSubscription(replaced)
            }
        }
    }

    /// Newest `updatedAt` first, ties by id. Each timestamp is parsed once, before the sort:
    /// inside the comparator it ran twice per comparison, i.e. ~1,400 parses per update at a
    /// hundred agents (P3). Same order and same tie-break as before. Also refreshes `agentDates`,
    /// which the incremental upsert path relies on.
    private func sortedAgents(_ agents: [AgentSnapshot]) -> [AgentSnapshot] {
        let parsed = agents.map { (agent: $0, date: PaseoDate.parse($0.updatedAt)) }
        let sorted = parsed.sorted { isNewer($0.agent, $0.date, than: $1.agent, $1.date) }
        for entry in parsed { agentDates[entry.agent.id] = entry.date }
        return sorted.map(\.agent)
    }

    /// Assigns a freshly fetched list and keeps the counts and the date cache in step.
    private func setAgents(_ newAgents: [AgentSnapshot]) {
        agents = newAgents
        let ids = Set(newAgents.map(\.id))
        agentDates = agentDates.filter { ids.contains($0.key) }
        refreshAgentCounts()
    }

    private func isNewer(
        _ lhs: AgentSnapshot, _ left: Date?, than rhs: AgentSnapshot, _ right: Date?
    ) -> Bool {
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
    // M8c: settable inside the module so ConversationFeatures can apply optimistic updates.
    public internal(set) var agent: AgentSnapshot?
    public private(set) var timeline = TimelineState()
    /// `TurnBuilder.turns(from: timeline.rows, activeTurnId: activeTurnId)`, kept in sync.
    public private(set) var turns: [Turn] = []
    /// The conversation's media (G12 C15), derived from `turns` on the same funnel:
    /// the sheet reads this, never the turns themselves.
    public private(set) var mediaIndex = ConversationMediaIndex()
    /// Per-turn usage points in completion order (G13 C16): frozen on the next
    /// turn's start, read by the context sheet's charts. Never reset by
    /// rewinds — spent cost stays spent. Settable inside the module (the M8c
    /// pattern) so `ConversationContext` owns the append rule.
    public internal(set) var turnUsage: [TurnUsagePoint] = []
    /// The still-open turn's collection (G13 C16): updated in place by every
    /// usage figure until the next `turn_started` freezes it.
    public internal(set) var openUsageTurnID: String?
    public internal(set) var openUsageTokens: Int?
    public internal(set) var openUsageCost: Double?
    /// The previous turn's final cumulative figures: the delta baseline. Reset
    /// by a session reset (a drop restarts the baseline instead of going negative).
    public internal(set) var baselineTokens: Int?
    public internal(set) var baselineCost: Double?
    /// The open turn's latest cumulative figures, promoted to the baseline on freeze.
    public internal(set) var openLatestTokens: Int?
    public internal(set) var openLatestCost: Double?
    /// The running turn. From the agent snapshot, made snappier by `turn_started`/`turn_completed`
    /// stream events.
    public private(set) var activeTurnId: String?
    public private(set) var isLoadingOlder = false
    /// Pending permission requests, oldest first. Seeded from the agent snapshot and kept live by
    /// `agent_permission_request`/`agent_permission_resolved` (and the stream's permission events).
    public private(set) var pendingPermissions: [AgentPermissionRequest] = []
    /// The provider's notice from the last accepted change, e.g. "applies next turn". Render as a
    /// toast; `clearNotice()` once shown.
    public internal(set) var lastNotice: AgentProviderNotice?
    /// Last failed send, cancel or agent change, for a transient error banner. Cleared by the next success.
    public internal(set) var actionError: String?
    /// Last failed background fetch (opening the conversation, older pages, catching up after a
    /// gap). Kept apart from `actionError` so a slow or timed-out refresh never appears on the
    /// composer: only the user's own send, cancel or settings change belongs there.
    public private(set) var backgroundError: String?
    /// The composer text. Lives here so it survives navigating away and back.
    public var draft = ""
    /// In-conversation search (find bar). Owned here so results survive view churn.
    public let search: ConversationSearch
    /// Provider-managed subagents for this agent's track.
    public let subagents: ConversationSubagents
    /// Every user prompt of the conversation, from the daemon's index (U5 chat outline).
    public let promptOutline: PromptOutline
    public let backgroundWork: BackgroundWorkStore
    /// File uploads for this conversation (`file.upload.request` + binary frames).
    public let uploads: ConversationUpload

    internal let client: (any DaemonClient)?
    private var isCatchingUp = false
    /// Incremental `TurnBuilder`: keeps the last built turns so streaming a token rebuilds only the
    /// newest turn instead of the whole transcript. See `IncrementalTurnBuilder`.
    private let turnBuilder = IncrementalTurnBuilder()
    /// Number of `updateTurns()` commits. Test probe for the coalescing guarantee.
    internal private(set) var turnCommits = 0

    /// True while the agent works: an active turn, or status `.running`.
    public var isRunning: Bool { activeTurnId != nil || agent?.status == .running }

    init(agentId: String) {
        self.agentId = agentId
        self.client = nil
        self.search = ConversationSearch(agentId: agentId, client: nil)
        self.subagents = ConversationSubagents(agentId: agentId, client: nil)
        self.promptOutline = PromptOutline(agentId: agentId, client: nil)
        self.backgroundWork = BackgroundWorkStore(agentId: agentId, client: nil)
        self.uploads = ConversationUpload(client: nil)
    }

    internal init(agentId: String, client: any DaemonClient) {
        self.agentId = agentId
        self.client = client
        self.search = ConversationSearch(agentId: agentId, client: client)
        self.subagents = ConversationSubagents(agentId: agentId, client: client)
        self.promptOutline = PromptOutline(agentId: agentId, client: client)
        self.backgroundWork = BackgroundWorkStore(agentId: agentId, client: client)
        self.uploads = ConversationUpload(client: client)
        // R18: relay endpoints cap upload chunks (ConversationUpload.chunkSize(relay:)).
        self.uploads.isRelayConnection = (client as? DaemonConnection)?.endpoint.relay != nil
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
            backgroundError = nil
            // Opening a conversation is deliberate focus: acknowledge attention on the daemon.
            if agent?.requiresAttention == true { await clearAttention() }
        } catch {
            if timeline.rows.isEmpty {
                phase = .failed(errorText(error))
            } else {
                backgroundError = errorText(error)
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
            backgroundError = nil
        } catch {
            backgroundError = errorText(error)
        }
    }

    /// Sends `text` (trimmed; no-op when empty). Shows it at once as a pending row, then sends
    /// `SendAgentMessageRequest` with a fresh `messageId`. When the agent is running, the plain
    /// call steers (`activeTurnBehavior: "steer"`); pass `behavior: "interrupt"` to interrupt the
    /// turn instead (the wire also supports `"steer"`). Clears `draft` when `text == draft`.
    public func send(_ text: String, behavior: String? = nil) async {
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
                    activeTurnBehavior: behavior ?? (isRunning ? "steer" : nil)))
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
            freezeOpenUsage()
            openUsageTurnID = turnId

        case .turnCompleted(let turnId, let usage):
            setActiveTurn(nil)
            if let usage {
                applyContextWindow(usage)
                recordTurnUsage(turnId: turnId, provider: agent?.provider, usage: usage)
            }

        case .usageUpdated(let eventProvider, let usage, let turnId):
            if let usage {
                applyContextWindow(usage)
                recordTurnUsage(
                    turnId: turnId, provider: eventProvider ?? agent?.provider, usage: usage)
            }

        case .turnFailed, .turnCanceled:
            setActiveTurn(nil)

        case .permissionRequested(let raw):
            if let request = try? raw.decoded(as: AgentPermissionRequest.self) {
                addPermission(request)
            }

        case .permissionResolved(let requestId):
            removePermission(requestId: requestId)

        case .timeline:
            switch applyTimelineDeltas([payload]) {
            case .applied, .unchanged:
                break
            case .gap:
                await catchUp()
            case .epochChanged:
                await load()
            }

        default:
            break
        }
    }

    /// The outcome of applying a batch of live timeline deltas.
    internal enum TimelineBatchResult: Sendable {
        /// At least one delta applied; the turns were committed once.
        case applied
        /// Nothing applied (every delta was a duplicate or ignored).
        case unchanged
        /// A delta was missed; the store must catch up from the daemon.
        case gap
        /// The epoch changed; the store must reload the tail.
        case epochChanged
    }

    /// Applies consecutive live timeline deltas in one batch and commits the turns once.
    /// Payloads after a gap or an epoch change are left unapplied: the catch-up fetch covers
    /// them, and applying them against a stale `nextSeq` would only report more gaps.
    internal func applyTimelineDeltas(_ payloads: [AgentStreamPayload]) -> TimelineBatchResult {
        var appliedAny = false
        var failure: TimelineBatchResult = .unchanged
        for payload in payloads {
            guard payload.agentId == agentId, case .timeline = payload.event else { continue }
            switch timeline.applyStream(payload) {
            case .applied:
                appliedAny = true
            case .gap:
                failure = .gap
            case .epochChanged:
                failure = .epochChanged
            case .duplicate, .ignored:
                continue
            }
            if failure != .unchanged { break }
        }
        guard appliedAny else { return failure }
        updateTurns()
        return failure == .unchanged ? .applied : failure
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
                backgroundError = nil
                guard page.hasNewer else { return }
                guard let next = timeline.endCursor, next != cursor else { return }
                cursor = next
            } catch {
                backgroundError = errorText(error)
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

    internal func rollBackSend(clientId: String, text: String, error: String) {
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
        turnCommits += 1
        turns = turnBuilder.turns(from: timeline.rows, activeTurnId: activeTurnId)
        mediaIndex.update(turns: turns)
        // The chat outline is stale whenever the newest prompt moves (a turn started, a page
        // arrived, the timeline was replaced). Upstream's `latestPromptSeq` effect.
        promptOutline.timelineChanged(epoch: timeline.epoch, latestPromptSeq: latestPromptSeq)
    }

    /// The newest prompt row on the wire, cached by `TimelineState` so this is O(1).
    /// Pending sends are not in the daemon's index yet.
    private var latestPromptSeq: Int? { timeline.latestPromptSeq }

    /// Upstream `planTimelinePromptJump` (`app/src/timeline/timeline-sync-plan.ts:77-88`): a
    /// bounded window starting half a page above the prompt, merged outside the loaded range.
    public nonisolated static func promptJumpCursor(
        epoch: String, seq: Int, pageSize: Int = 40
    ) -> TimelineCursor {
        TimelineCursor(epoch: epoch, seq: seq + pageSize / 2 + 1)
    }

    /// The view id of the prompt's own row when its window is loaded. The chat transcript tags
    /// every row `row:<seqEnd>` (`ChatTurns`), which works for a prompt inside a running turn too.
    public func promptRowId(forPromptSeq seq: Int) -> String? {
        guard let row = timeline.rows.first(where: { row in
            guard !row.isPending, case .userMessage = row.item else { return false }
            return row.seqStart == seq
        }) else { return nil }
        return "row:\(row.seqEnd)"
    }

    /// Jumps to a prompt without paging history in: a loaded prompt returns its row directly; an
    /// unloaded one fetches just the window around it (upstream `jumpToPrompt`,
    /// `use-chat-outline.ts:235-266`) and returns the row once merged. Nil when it failed.
    @discardableResult
    public func jump(toPromptSeq seq: Int) async -> String? {
        if let rowId = promptRowId(forPromptSeq: seq) { return rowId }
        guard let client, let epoch = timeline.epoch else { return nil }
        var request = FetchAgentTimelineRequest(
            agentId: agentId, direction: .before,
            cursor: Self.promptJumpCursor(epoch: epoch, seq: seq), limit: 40)
        // The window is usually outside the contiguous range; the daemon must merge, not continue.
        request.mergeWindow = true
        do {
            let page = try await client.send(request)
            if let message = page.error {
                backgroundError = message
                return nil
            }
            timeline.applyPage(page)
            if let snapshot = page.agent { applyAgent(snapshot) }
            updateTurns()
            backgroundError = nil
            return promptRowId(forPromptSeq: seq)
        } catch {
            backgroundError = conversationErrorText(error)
            return nil
        }
    }

    /// Optimistic bubble for a send performed by a feature extension.
    internal func showPendingSend(text: String, clientId: String, timestamp: String) {
        timeline.addPendingUserMessage(text: text, clientMessageId: clientId, timestamp: timestamp)
        updateTurns()
    }

    internal func markSendAccepted() { actionError = nil }

    internal static func nowTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

/// Coalesces consecutive `.timeline` stream payloads for one agent so the observable
/// transcript commits at most once per display frame.
///
/// The first payload after an idle window commits immediately (leading edge), so the first
/// token of a turn is not delayed. Payloads that arrive while the frame timer is pending are
/// buffered and committed together when it fires (trailing edge / ceiling). Nothing is dropped:
/// every payload is applied when the buffer flushes, so the store always holds the full text.
@MainActor
internal final class TimelineCommitCoalescer {
    /// The store to commit. Applying a batch is synchronous; only a gap or an epoch change
    /// needs a follow-up task.
    private let store: ConversationStore
    /// The coalescing window: one display frame at 60 Hz.
    private let frameInterval: Duration
    private var pending: [AgentStreamPayload] = []
    private var timer: Task<Void, Never>?
    private var lastFlushAt: ContinuousClock.Instant?

    internal init(store: ConversationStore, frameInterval: Duration = .milliseconds(16)) {
        self.store = store
        self.frameInterval = frameInterval
    }

    /// Buffers one live delta. Commits synchronously when the stream has been idle for a frame.
    internal func enqueue(_ payload: AgentStreamPayload) {
        pending.append(payload)
        guard timer == nil else { return }

        let elapsed = lastFlushAt.map { ContinuousClock.now - $0 } ?? frameInterval
        if elapsed >= frameInterval {
            flush()
        }
        arm()
    }

    /// Commits everything buffered now. Used by the frame timer and by tests.
    internal func flush() {
        guard !pending.isEmpty else { return }
        timer?.cancel()
        timer = nil
        let payloads = pending
        pending = []
        lastFlushAt = ContinuousClock.now
        let signpost = PaseoSignpost.log.beginInterval("stream commit")
        defer { PaseoSignpost.log.endInterval("stream commit", signpost) }
        switch store.applyTimelineDeltas(payloads) {
        case .applied, .unchanged:
            break
        case .gap:
            Task { await store.catchUp() }
        case .epochChanged:
            Task { await store.load() }
        }
    }

    private func arm() {
        timer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.frameInterval)
            self.timer = nil
            self.flush()
            if !self.pending.isEmpty {
                self.arm()
            }
        }
    }
}

/// One readable line for an error, for `agentsError` / `actionError`.
private func errorText(_ error: Error) -> String {
    if let error = error as? LocalizedError, let description = error.errorDescription {
        return description
    }
    return String(describing: error)
}
