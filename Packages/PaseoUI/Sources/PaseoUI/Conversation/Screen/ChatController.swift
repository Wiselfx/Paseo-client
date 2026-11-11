#if canImport(UIKit)
import Observation
import PaseoStore
import SwiftUI
import Synchronization
import UIKit
import UniformTypeIdentifiers

// MARK: - Actions

/// The transcript's verbs, in the environment so a turn row can call them without taking a dozen
/// closures in its init (R6 §4). One instance per open agent, created by `ChatController`.
///
/// It is `@Observable` only so a flag can change without rebuilding the rows; the closures
/// themselves are stable for the controller's life.
@MainActor @Observable final class ChatActions {
    /// Opens the workspace file viewer at a path (prose links, Read/Edit/Write rows).
    var openFile: (String) -> Void = { _ in }
    /// Markdown interactions that are not links: copy code, and anything else the prose reports.
    var markdown: (MarkdownAction) -> Void = { _ in }
    /// Asks for the can't-undo confirmation of a rewind (scope + message id).
    var rewind: (RewindScope, String) -> Void = { _, _ in }
    /// Edit: confirm, rewind, put the text back in the composer.
    var edit: (String, String) -> Void = { _, _ in }
    /// Rerun: confirm, rewind, resend the text.
    var rerun: (String, String) -> Void = { _, _ in }
    /// Fork at the row above `row` (nil for the in-flight fork of the whole timeline).
    var fork: ((ClaudeForkTarget, TimelineRow) async -> Void)?
    /// The running turn's fork: no boundary.
    var forkInFlight: ((ClaudeForkTarget) async -> Void)?
    /// DSH "Delete this turn".
    var deleteTurn: ((TimelineRow) -> Void)?
    /// DSH "Retract this message".
    var retract: ((TimelineRow) -> Void)?
    /// Reads a workspace image for prose. Decoded off main and cached by (workspace, path).
    var loadImage: (String) async -> UIImage? = { _ in nil }

    /// What this agent and host can actually do with a turn, as one value the rows compare
    /// (R-2). Recomputed by `ChatController` when the agent snapshot, the host features or the
    /// workspace capabilities change — never in a row body (R-1).
    var availability = TurnActionAvailability()

    private let store: ConversationStore

    init(store: ConversationStore) {
        self.store = store
    }

    /// The projected row directly above `userRow` — the cut boundary for Retract and Delete this
    /// turn. O(1): the timeline's seqEnd index answers with one dictionary lookup (R3 §1).
    func cutRow(for userRow: TimelineRow) -> TimelineRow? {
        let rows = store.timeline.rows
        guard let index = store.timeline.rowIndex(forSeqEnd: userRow.seqEnd), index > 0 else {
            return nil
        }
        return rows[index - 1]
    }
}

private struct ChatActionsKey: EnvironmentKey {
    static let defaultValue: ChatActions? = nil
}

extension EnvironmentValues {
    /// The open conversation's verbs; nil outside a conversation (previews, the draft screen).
    var chatActions: ChatActions? {
        get { self[ChatActionsKey.self] }
        set { self[ChatActionsKey.self] = newValue }
    }
}

// MARK: - Turn action availability

/// What the open agent can actually do with a turn. One value, computed once per agent/host
/// capability change by `ChatController` and passed to rows (R-2), so a provider that cannot
/// rewind or fork never shows an action that would fail.
///
/// Upstream's conditions:
/// - **Rewind** (`use-rewind-capabilities.ts:32-56`, `message.tsx:531`): the agent's
///   `capabilities.supportsRewind*` flags, under the host's `features.rewind`. Our
///   `rewindMenuScopes` is exactly that list.
/// - **Edit / Rerun** (`composer-restore.tsx`): rewind to the conversation, then restore the
///   text. Offered when the conversation scope can be rewound.
/// - **Fork** (`use-fork-agent.ts`: `useHostFeature(serverId, "agentForkContext")`): the host
///   feature and a shell that can open the new agent. A completed turn pins a boundary
///   (`turn-boundary.ts:9-24`), which needs `features.agentForkContextCursor` — the only
///   boundary this client sends (`ForkContextRequest.boundaryCursor`). The running turn forks
///   with no boundary and needs neither.
/// - **Retract this message / Delete this turn** are forks at a cut row (DSH
///   `message-actions.ts:195-260`): the same boundary fork as a completed turn, *not* rewind.
struct TurnActionAvailability: Sendable, Equatable {
    /// Scopes the provider offers on your bubbles, in menu order; empty hides rewind.
    var rewindChoices: [RewindScope] = []
    /// Edit/Rerun exist: the conversation can be rewound.
    var canRewrite = false
    /// Fork with no boundary: the running turn's footer (`turn-footer.tsx:38-46`).
    var canForkInFlight = false
    /// Fork pinned to a boundary: the completed turn's footer, retract, delete this turn.
    var canForkAtBoundary = false
    /// The workspace target is offered beside the tab target: the host can create one.
    var canForkWorkspace = false
}

// MARK: - Find state

/// The find-in-conversation session's view state. The matches themselves live in
/// `ConversationStore.search`, so they survive view churn; this is what the views draw.
@MainActor @Observable final class ChatFind {
    var isOpen = false
    var query = ""
    var index = 0
    /// The seqEnd whose row flashes after a step.
    var flash: Int?
    /// The turn the reader was nearest when find opened; closing restores it.
    var anchor: String?
    /// A scroll the transcript owes after a step or a search result. Cleared by the transcript.
    var jump: FindJump?
    var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        task = nil
        query = ""
        index = 0
        flash = nil
        anchor = nil
        jump = nil
    }
}

/// One pending find scroll: the row's seqEnd and whether to animate it.
struct FindJump: Equatable {
    var seq: Int
    var animated: Bool
}

/// A recorded jump intent: the transcript performs the scroll (it owns the scroll handles).
struct TranscriptJump: Equatable {
    var id: String
}

// MARK: - Controller

/// Everything the conversation screen does that is not a SwiftUI handle: state that must survive a
/// body re-evaluation, and the ops the views call. One per open agent, in the screen's `@State`.
///
/// Nothing here is read by `ChatScreen.body` except `find.isOpen`; each child view reads only the
/// properties it draws, so typing re-evaluates the composer and streaming re-evaluates the last
/// turn row and the status line.
@MainActor @Observable final class ChatController {
    let session: HostSession
    let store: ConversationStore

    /// The shell's callbacks, forwarded unchanged.
    var onOpenSidebar: (() -> Void)?
    var onOpenPanel: (() -> Void)?
    var onBack: (() -> Void)?
    var onNewAgent: ((String) -> Void)?
    var onForkAgent: ((String) -> Void)?
    var onOpenAgent: ((String) -> Void)?

    /// The transcript's verbs, put in the environment by `ChatScreen`.
    let actions: ChatActions
    /// The cards' verbs (G1 §1.2): the same instance for the screen's life, so it is never
    /// part of any row's `==`. Wired once in `configureActions`; cards read values from it.
    let richActions = RichActions()

    // Sheet routing.
    var sheet: ClaudeChatSheet?
    var showContextSheet = false
    var showFullScreenComposer = false
    var openFilePath: String?

    // Find.
    let find = ChatFind()

    // Follow and anchor.
    var isFollowing = true
    var anchoringToAnswer = false
    /// "Back to the end" is on screen. Set by the transcript from its distance from the end: it
    /// flips only when that distance crosses a real screen, never per scroll frame (D1 §3, H2 §2).
    var showsBackToEnd = false
    /// The header is out of the way while you read forward. The transcript owns the rule (its
    /// scroll distance accumulates in a non-observed box) and writes this one `Bool` only when
    /// the bar flips; only the top chrome reads it (H2 §3).
    var headerHidden = false
    /// A jump the transcript still owes (`jumpToPrompt` records it here).
    var pendingJump: TranscriptJump?

    // Rewind, message actions, rename, archive.
    var pendingRewind: PendingRewind?
    var rewindInFlight = false
    var pendingMessageAction: PendingMessageAction?
    var renamingAgent = false
    var renameText = ""
    var archiveConfirm = false

    // Permission lines and provider rows.
    var permissionResolvedLines: [AnsweredPermission] = []
    var hiddenSubagentIds: Set<String> = []

    // Slash commands.
    var slashCommands: [AgentSlashCommand] = []
    var slashState: SlashCommandState = .idle
    var slashError: String?

    // Mentions.
    var mentionIndex = MentionIndex()
    var mentionMatches: [MentionIndexRow] = []
    var recentMentions: [String] = []
    var mentionDebounce: Task<Void, Never>?

    // The queue and the attachment tray are app-scoped stores: they survive agent switches.
    var composerQueue = ComposerQueueStore.shared
    var attachmentStore = ComposerAttachmentStore.shared

    // Dictation and realtime voice.
    var dictation = DictationController()
    let voiceEngine = VoiceAudioEngine()

    // The mascot's machine and its one-shot baselines.
    var mascot = MascotStateMachine()
    var showCostBubble = false
    var signalledToolFailureIds: Set<String> = []
    var compactionOpen = false
    var attentionActive = false
    var mascotSeeded = false
    var mascotSeqFloor = Int.max
    var mascotLiveTurnId: String?

    /// An inline prose image the reader tapped, for the full-screen viewer (`ChatSheets`).
    var inlineImage: InlineProseImage?

    /// The shell's toast center, injected by `ChatScreen` (`@Environment(\.toast)`).
    var toastCenter: ToastCenter?

    private var draftSaveTask: Task<Void, Never>?
    /// Re-arms itself on each agent/host capability change; see `startAvailabilityTracking`.
    private var availabilityTask: Task<Void, Never>?
    /// Inline images, by `(workspaceId, path)`. Bounded by count and bytes: a long conversation
    /// full of screenshots must not hold every decoded bitmap for the life of the screen (H5
    /// round 2). `loadImage` passes a real cost, or `totalCostLimit` could never bite.
    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    /// The §12 network signal (G2). Owned here so its life matches the conversation's; cards
    /// read only the derived condition on `RichActions` (R-1).
    private var pathMonitor: NetworkPathMonitor?

    enum SlashCommandState {
        case idle, loading, ready
    }

    init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onOpenPanel: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil, onForkAgent: ((String) -> Void)? = nil,
        onOpenAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        self.onOpenSidebar = onOpenSidebar
        self.onOpenPanel = onOpenPanel
        self.onBack = onBack
        self.onNewAgent = onNewAgent
        self.onForkAgent = onForkAgent
        self.onOpenAgent = onOpenAgent
        self.actions = ChatActions(store: store)
        configureActions()
    }

    /// The closures `TurnRow` and its children call. They read the store at fire time, never in a
    /// body, so wiring them here does not subscribe anything.
    private func configureActions() {
        actions.openFile = { [weak self] path in
            self?.openFileViewer(at: path)
        }
        actions.markdown = { [weak self] action in
            self?.handleMarkdown(action)
        }
        actions.rewind = { [weak self] scope, messageId in
            self?.pendingRewind = PendingRewind(messageId: messageId, scope: scope)
        }
        actions.edit = { [weak self] messageId, text in
            self?.pendingMessageAction = PendingMessageAction(
                messageId: messageId, text: text, kind: .edit)
        }
        actions.rerun = { [weak self] messageId, text in
            self?.pendingMessageAction = PendingMessageAction(
                messageId: messageId, text: text, kind: .rerun)
        }
        actions.fork = { [weak self] target, row in
            await self?.forkInto(target, boundary: row.seqEnd)
        }
        actions.forkInFlight = { [weak self] target in
            await self?.forkInto(target, boundary: nil)
        }
        actions.deleteTurn = { [weak self] row in
            self?.deleteTurn(userRow: row)
        }
        actions.retract = { [weak self] row in
            self?.retractMessage(userRow: row)
        }
        richActions.daemonWorkspaceID = store.agent?.workspaceId
        richActions.openFile = { [weak self] path in
            self?.openFileViewer(at: path)
        }
        richActions.addImageToChat = { [weak self] fileName, data in
            guard let self else { return }
            self.attachmentStore.addImage(
                data: data, fileName: fileName, to: self.store.agentId, store: self.store)
        }
        // The pipeline's only daemon entry: socket bytes in, decoded pixels out. The fetch
        // reads the live agent at call time and runs off main inside the driver. Registered
        // per workspace (last registration wins) and unregistered in `deinit`, so a stale
        // controller never answers — or blocks — another conversation's images.
        richActions.linkCondition = MediaLinkCondition(
            isRelay: session.isRelayConnection, offline: false)
        if let workspaceID = store.agent?.workspaceId {
            daemonFetchRegistration.retain(workspaceID: workspaceID)
            Task { @MainActor [weak self] in
                let token = await MediaPipeline.shared.registerDaemonFetch(
                    for: workspaceID,
                    { [weak self] ref, maxBytes in
                        // The resolver runs off the main actor; the store, the session and
                        // the checkout are main-actor isolated, so it hops once into
                        // `fetchDaemonMedia`, which suspends on the socket (never blocks).
                        await self?.fetchDaemonMedia(ref: ref, maxBytes: maxBytes) ?? .unavailable
                    })
                self?.daemonFetchRegistration.retain(token: token)
                self?.startMediaLinkUpdates()
            }
        } else {
            startMediaLinkUpdates()
        }
        refreshAvailability()
        startAvailabilityTracking()
        startConnectionRefresh()
    }

    /// One daemon read for the media pipeline (G2). A resolver is registered *for* its
    /// workspace and the checkout is per workspace, not per agent, so the only check is
    /// that the workspace descriptor still exists.
    private func fetchDaemonMedia(ref: DaemonFileRef, maxBytes: Int) async -> DaemonMediaResult {
        guard
            let descriptor = self.session.workspaceDirectory.workspace(
                id: ref.workspaceID)
        else { return .unavailable }
        let checkout = self.session.checkout(for: descriptor)
        do {
            let file = try await checkout.files.fetch(
                ref.path, maxBytes: maxBytes)
            guard file.encoding == .base64, let content = file.content,
                let data = Data(
                    base64Encoded: content,
                    options: [.ignoreUnknownCharacters])
            else { return .unavailable }
            return .bytes(
                DaemonFileBytes(data: data, revision: file.revision))
        } catch let error as PaseoStoreError {
            // The daemon stats before it transfers: over `maxBytes` it
            // answers "File is too large to display" with no file. That
            // text is the frozen reference's, so the match is
            // upstream-string-dependent — the one place that may know it.
            if case .missingFile(_, let message) = error,
                message?.localizedCaseInsensitiveContains("too large")
                    == true
            {
                return .tooLarge
            }
            return .unavailable
        } catch {
            return .unavailable
        }
    }

    /// The workspace id plus the registration token, for `deinit`. A small box so
    /// the values survive without isolation: written once in `configureActions`, read
    /// when the controller goes away. Unregistration only removes the entry holding its
    /// own token, so a dead controller never unregisters its successor.
    private let daemonFetchRegistration = DaemonFetchRegistration()

    deinit {
        // A dead controller must not resolve another screen's images. The actor hop
        // cannot run synchronously here, so the unregister rides an unstructured task
        // carrying only values (never self).
        let registration = daemonFetchRegistration.snapshot()
        if let workspaceID = registration.workspaceID, let token = registration.token {
            Task {
                await MediaPipeline.shared.unregisterDaemonFetch(
                    for: workspaceID, token: token)
            }
        }
    }

    // MARK: Media link condition (G2 §12)

    /// The host session can switch direct ↔ relay on reconnect: refresh the derived
    /// condition on every connection change. One write per change, never per frame;
    /// path changes arrive through the monitor and refresh the same way.
    private func startConnectionRefresh() {
        withObservationTracking {
            _ = session.connection
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshLinkCondition(
                    interface: self.pathMonitor?.interface ?? .wifi,
                    constrained: self.pathMonitor?.constrained ?? false,
                    offline: self.pathMonitor?.offline ?? false)
                self.startConnectionRefresh()
            }
        }
    }

    private func startMediaLinkUpdates() {
        let monitor = NetworkPathMonitor()
        monitor.onChange = { [weak self] interface, constrained, _, offline in
            guard let self else { return }
            self.refreshLinkCondition(
                interface: interface, constrained: constrained, offline: offline)
        }
        pathMonitor = monitor
        refreshLinkCondition(
            interface: monitor.interface, constrained: monitor.constrained,
            offline: monitor.offline)
    }

    private func refreshLinkCondition(
        interface: NetworkPathMonitor.Interface, constrained: Bool, offline: Bool
    ) {
        let linkInterface: MediaLinkCondition.Interface
        switch interface {
        case .wifi: linkInterface = .wifi
        case .cellular: linkInterface = .cellular
        case .wired: linkInterface = .wired
        case .other: linkInterface = .other
        }
        richActions.linkCondition = MediaLinkCondition(
            interface: linkInterface, constrained: constrained,
            isRelay: session.isRelayConnection, offline: offline)
    }

    // MARK: Turn actions

    /// The current availability value, O(1) in agent capabilities and host features.
    var turnActionAvailability: TurnActionAvailability {
        let choices = rewindMenuScopes
        let canFork = session.isForkContextSupportedByHost && onForkAgent != nil
        return TurnActionAvailability(
            rewindChoices: choices,
            canRewrite: canRewrite,
            canForkInFlight: canFork,
            // Our fork only pins a cursor boundary, which needs the host's cursor feature.
            canForkAtBoundary: canFork
                && session.serverInfo?.hasFeature("agentForkContextCursor") == true,
            canForkWorkspace: canFork && session.workspaceDirectory.supportsWorkspaceCreate)
    }

    /// Publishes the value and re-arms observation of the three inputs that can change it: the
    /// host features, this agent's snapshot (capabilities), and the workspace directory's
    /// create support. One task per controller; changes are rare, so this costs nothing per
    /// scroll frame or keystroke.
    private func startAvailabilityTracking() {
        guard availabilityTask == nil else { return }
        availabilityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Never hold `self` across the wait: a closed screen must deallocate, and the
                // task is owned by it.
                let inputs = { [weak self] () -> (HostSession, ConversationStore)? in
                    guard let self else { return nil }
                    self.refreshAvailability()
                    return (self.session, self.store)
                }()
                guard let (session, store) = inputs else { return }
                await ChatController.nextAvailabilityChange(session: session, store: store)
            }
        }
    }

    private func refreshAvailability() {
        let next = turnActionAvailability
        if actions.availability != next { actions.availability = next }
    }

    private static func nextAvailabilityChange(
        session: HostSession, store: ConversationStore
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = session.serverInfo
                _ = store.agent
                _ = session.workspaceDirectory.supportsWorkspaceCreate
            } onChange: {
                continuation.resume()
            }
        }
    }

    // MARK: Toast

    /// One line, through the shell's toast center (R4). No per-view toast state.
    func showToast(
        _ text: String, systemImage: String? = nil, undo: (() -> Void)? = nil
    ) {
        toastCenter?.show(text, systemImage: systemImage, undo: undo)
    }

    // MARK: Capabilities

    /// Scopes the rewind menu shows: host feature gate + the provider's advertised flags, verbatim.
    var rewindMenuScopes: [RewindScope] {
        guard session.isRewindSupportedByHost else { return [] }
        return store.rewindCapabilities.menu
    }

    /// Scope used by Edit/Rerun: prefer conversation-only; fall back to both. Nil hides them.
    var rewriteScope: RewindScope? {
        let scopes = rewindMenuScopes
        return scopes.contains(.conversation) ? .conversation : (scopes.contains(.both) ? .both : nil)
    }

    var canRewrite: Bool { rewriteScope != nil }

    // MARK: Header

    func beginRename() {
        renameText = store.agent?.title ?? ""
        renamingAgent = true
    }

    func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await store.rename(to: trimmed) }
    }

    func copyAgentId() {
        Clipboard.copy(store.agentId)
        Haptics.light()
        showToast("Agent ID copied")
    }

    /// Archive at once when idle; while running, ask first (the existing confirmation text).
    func archiveAgent() {
        if store.isRunning {
            archiveConfirm = true
            return
        }
        Haptics.light()
        Task { await archiveNow() }
    }

    func archiveNow() async {
        let agentId = store.agentId
        await store.archive()
        await session.refreshAgents()
        showToast("Agent archived", undo: { [weak self] in
            guard let self else { return }
            Task {
                _ = await self.session.agentLifecycle.unarchive(agentId: agentId)
                await self.session.refreshAgents()
            }
        })
    }

    func newAgent(draft: String) {
        onNewAgent?(draft)
    }

    func openFileViewer(at path: String) {
        openFilePath = path
    }

    // MARK: Find

    func openFind(anchor: String?) {
        Haptics.selection()
        guard !find.isOpen else { return }
        find.anchor = anchor
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            find.isOpen = true
        }
    }

    func closeFind() {
        Haptics.selection()
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            find.isOpen = false
        }
        find.reset()
        store.search.clear()
    }

    /// The seqEnd of the match currently on screen; nil when the results are empty.
    var findSeq: Int? {
        let locations = store.search.locations
        guard find.index < locations.count else { return nil }
        return locations[find.index].seq
    }

    func stepFind(_ delta: Int) {
        let count = store.search.locations.count
        guard count > 0 else { return }
        let next = min(max(0, find.index + delta), count - 1)
        guard next != find.index else { return }
        find.index = next
        requestFindScroll(animated: true)
    }

    func requestFindScroll(animated: Bool) {
        guard let seq = findSeq else { return }
        flash(seq)
        find.jump = FindJump(seq: seq, animated: animated)
    }

    func flash(_ seq: Int) {
        find.flash = seq
        let captured = seq
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if find.flash == captured { find.flash = nil }
        }
    }

    func scheduleSearch(_ query: String) {
        find.task?.cancel()
        find.task = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            store.search.clear()
            return
        }
        find.task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.store.search.search(trimmed)
            self.find.index = 0
            self.requestFindScroll(animated: true)
        }
    }

    // MARK: Jumps

    /// A rail tick or a sheet row: a loaded prompt is scrolled to now; an unloaded one fetches
    /// just its window first. The transcript performs the scroll (`pendingJump`).
    func jumpToPrompt(_ seq: Int) {
        isFollowing = false
        Task { [weak self] in
            guard let self, let rowId = await self.store.jump(toPromptSeq: seq) else { return }
            self.pendingJump = TranscriptJump(id: rowId)
        }
    }

    // MARK: Rewind and message actions

    var messageActionTitle: String {
        pendingMessageAction?.kind == .edit ? "Rewind and edit?" : "Rewind and rerun?"
    }

    func messageActionDescription(for action: PendingMessageAction) -> String {
        let scopeName = rewriteScope == .both ? "the conversation and files" : "the conversation"
        switch action.kind {
        case .edit:
            return "Rewinds \(scopeName) to before this message, and puts its text back in your draft. This action cannot be undone."
        case .rerun:
            return "Rewinds \(scopeName) to before this message, and runs the same prompt again. This action cannot be undone."
        }
    }

    /// Runs the confirmed Edit/Rerun.
    func performMessageAction(_ action: PendingMessageAction) async {
        guard let scope = rewriteScope else { return }
        let failure = await store.rewind(toMessageId: action.messageId, scope: scope)
        if let failure {
            showToast(failure)
            return
        }
        switch action.kind {
        case .edit:
            store.draft = action.text
            showToast("Rewound — the text is back in your draft.")
        case .rerun:
            await store.send(action.text)
        }
    }

    /// Runs the confirmed rewind and toasts the outcome. One confirm in flight at a time.
    func performPendingRewind(_ rewind: PendingRewind) {
        guard !rewindInFlight else { return }
        rewindInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let failure = await self.store.rewind(toMessageId: rewind.messageId, scope: rewind.scope)
            self.rewindInFlight = false
            if let failure {
                self.showToast(failure)
            } else {
                // The timeline is truncated away from the rewound point; resume tail-follow.
                self.anchoringToAnswer = false
                self.isFollowing = true
                self.showToast("Rewound")
            }
        }
    }

    // MARK: Fork

    /// Forks into the chosen target and opens the new agent.
    func forkInto(_ target: ClaudeForkTarget, boundary: Int?) async {
        switch target {
        case .tab:
            await openForkedAgent(
                await store.forkConversation(fromBoundarySeq: boundary), toast: "Forked")
        case .workspace:
            guard let workspaceId = await createForkWorkspace() else { return }
            await openForkedAgent(
                await store.forkConversation(fromBoundarySeq: boundary, into: workspaceId),
                toast: "Forked")
        }
    }

    /// Retract: fork before the message, then hand the text back in the new session's composer.
    func retractMessage(userRow: TimelineRow) {
        guard let boundary = actions.cutRow(for: userRow),
            case .userMessage(let message) = userRow.item
        else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.openForkedAgent(
                await self.store.forkConversation(fromBoundarySeq: boundary.seqEnd),
                toast: "The message is back in the composer", draft: message.text)
        }
    }

    /// Delete this turn: fork before the turn's prompt and keep the prefix only.
    func deleteTurn(userRow: TimelineRow) {
        guard let boundary = actions.cutRow(for: userRow) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.openForkedAgent(
                await self.store.forkConversation(fromBoundarySeq: boundary.seqEnd),
                toast: "The turn is absent from the new session")
        }
    }

    /// Creates the workspace "Fork in a new workspace" lands in, through the sidebar's create path.
    func createForkWorkspace() async -> String? {
        let directory = session.workspaceDirectory
        guard let agent = store.agent, let workspaceId = agent.workspaceId,
            let workspace = directory.workspace(id: workspaceId),
            let project = directory.projects.first(where: { $0.projectId == workspace.projectId })
        else {
            showToast("This agent is not in a workspace.")
            return nil
        }
        if !directory.supportsWorkspaceCreate {
            showToast("This host can't create worktree workspaces.")
            return nil
        }
        let base = forkBaseBranch(in: project)
        let branch = "workspace-\(Int(Date().timeIntervalSince1970))"
        let created = await directory.createWorkspace(
            in: project,
            source: .branchOff(
                baseRef: base.hasPrefix("refs/") ? base : "refs/heads/\(base)",
                branchName: branch, worktreeSlug: branch))
        guard let created else {
            if let failure = directory.actionError { showToast(failure) }
            return nil
        }
        return created.id
    }

    /// The branch a fork's worktree cuts from: the project's local checkout, else any branch.
    func forkBaseBranch(in project: WorkspaceProjectDescriptor) -> String {
        let workspaces = session.workspaceDirectory.workspaces.filter {
            $0.projectId == project.projectId
        }
        if let branch = workspaces.first(where: { $0.workspaceKind != .worktree && $0.branch != nil })?
            .branch
        {
            return branch
        }
        return workspaces.compactMap(\.branch).first ?? "main"
    }

    /// The tail every fork shares: surface the failure, refresh the sidebar, say what happened,
    /// open the new agent. An optional `draft` seeds its composer.
    func openForkedAgent(
        _ result: (agentId: String?, error: String?), toast: String, draft: String? = nil
    ) async {
        if let failure = result.error {
            showToast(failure)
            return
        }
        guard let newId = result.agentId else { return }
        await session.refreshAgents()
        if let draft { session.conversation(for: newId).draft = draft }
        showToast(toast)
        onForkAgent?(newId)
    }

    // MARK: Send

    var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Called by the composer after it has checked `canSend`. Behaviour is the send button's
    /// (steer/queue/interrupt) choice.
    func send(behavior: String? = nil, attachments: [AgentAttachment]) {
        dictation.stop(keepingDraft: true)
        SavedDraftStore.clear(store.agentId)
        anchoringToAnswer = true
        isFollowing = false
        Haptics.send()
        // Capture the text before the hop: the store clears the draft as it sends.
        let text = trimmedDraft
        Task { [weak self] in
            guard let self else { return }
            await self.store.sendWithAttachments(
                text, attachments: attachments, behavior: behavior)
            if self.store.actionError == nil {
                self.attachmentStore.consumeDoneAttachments(for: self.store.agentId)
            }
        }
    }

    /// Sends text the reader chose to queue or retracted from the timeline.
    func sendText(_ text: String) {
        anchoringToAnswer = true
        isFollowing = false
        Haptics.send()
        Task { [weak self] in
            await self?.store.send(text)
        }
    }

    // MARK: Queue

    var isQueueNonEmpty: Bool {
        !composerQueue.queue(for: store.agentId).isEmpty
    }

    /// Long-press on the send button: holds the draft back until the running turn ends.
    func queueDraft(attachments: [ComposerAttachmentItem]) {
        guard attachments.isEmpty else {
            showToast("Remove attachments to queue")
            return
        }
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        composerQueue.mutate(store.agentId) { _ = $0.enqueue(text) }
        store.draft = ""
        Haptics.medium()
    }

    /// A turn ended: dequeue the head and send it.
    func flushQueuedMessage() {
        var next: MessageQueue.QueuedMessage?
        composerQueue.mutate(store.agentId) { next = $0.dequeueNext(isIdle: true) }
        guard let next else { return }
        anchoringToAnswer = true
        isFollowing = false
        Task { [weak self] in
            guard let self else { return }
            await self.store.send(next.text)
            self.composerQueue.mutate(self.store.agentId) { $0.finishSending() }
        }
    }

    /// Moves a queued message back into the draft (replacing it, or appending on a new line).
    /// Returns true so the composer can focus its field.
    func editQueuedMessage(_ message: MessageQueue.QueuedMessage) -> Bool {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return false }
        if store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.draft = text
        } else {
            store.draft += "\n" + text
        }
        return true
    }

    /// Immediate steer of a queued message, cutting the line.
    func sendQueuedNow(_ message: MessageQueue.QueuedMessage) {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return }
        sendText(text)
    }

    // MARK: Saved drafts

    /// Restores the persisted draft when the conversation opens and the store's draft is empty.
    func seedSavedDraft() {
        guard store.draft.isEmpty else { return }
        let saved = SavedDraftStore.load(store.agentId)
        if !saved.isEmpty { store.draft = saved }
    }

    /// Debounced write of the draft (~500 ms) to UserDefaults, cleared on send.
    func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        let agentId = store.agentId
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            SavedDraftStore.save(agentId, value)
        }
    }

    // MARK: Slash

    /// Loads the agent's slash commands once per appearance. The store caches them per agent.
    func loadSlashCommands() async {
        guard slashState == .idle else { return }
        slashState = .loading
        let loaded = await session.hostSettings.loadCommands(for: store.agentId)
        slashCommands = loaded
        slashError = session.hostSettings.commandError(for: store.agentId)
        slashState = .ready
    }

    /// The query while the draft is exactly one slash-command token, else nil.
    func slashQuery(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let body = text.dropFirst()
        if body.contains(where: { $0.isWhitespace }) { return nil }
        return String(body)
    }

    func filteredSlashCommands(for query: String?) -> [AgentSlashCommand] {
        guard let query, !query.isEmpty else { return slashCommands }
        let lowered = query.lowercased()
        return slashCommands.filter { $0.name.lowercased().hasPrefix(lowered) }
    }

    /// The composer's placeholder: the generic upstream string, in both modes.
    var composerPrompt: String {
        // Upstream `composer.placeholders.mobile` (en.ts:117).
        "Message, @files, /commands"
    }

    // MARK: Mentions

    /// The open workspace's checkout (same pattern as the inline image loader).
    var mentionCheckout: CheckoutStore? {
        guard let workspaceId = store.agent?.workspaceId,
            let descriptor = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        return session.checkout(for: descriptor)
    }

    /// Builds the file index once, then filters locally.
    func loadMentionIndexIfNeeded() async {
        guard let checkout = mentionCheckout else { return }
        await mentionIndex.build(using: checkout.files)
        if let query = ChatMentions.query(in: store.draft) {
            mentionMatches = mentionIndex.matches(query: query, recent: recentMentions)
        }
    }

    /// The mention popover's debounce, driven by the composer's draft observer.
    func handleMentionQuery(_ query: String?) {
        mentionDebounce?.cancel()
        guard let query, !query.isEmpty else {
            mentionMatches = []
            return
        }
        let needsIndex = mentionIndex.rows.isEmpty
        mentionDebounce = Task { [weak self] in
            if needsIndex { await self?.loadMentionIndexIfNeeded() }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.mentionMatches = self.mentionIndex.matches(
                query: query, recent: self.recentMentions)
        }
    }

    func handleMentionPick(_ row: MentionIndexRow) {
        Haptics.selection()
        if row.isDirectory {
            // Drill in: keep the popover open, token becomes `@path/`.
            replaceMentionToken(with: row.path + "/")
        } else {
            replaceMentionToken(with: row.path + " ")
            recentMentions.removeAll { $0 == row.path }
            recentMentions.insert(row.path, at: 0)
            if recentMentions.count > 8 { recentMentions.removeLast() }
        }
    }

    /// Replaces the trailing `@token` with `replacement` (mention insert / drill-in).
    func replaceMentionToken(with replacement: String) {
        let text = store.draft
        guard let at = text.lastIndex(of: "@") else { return }
        let before = text[..<at]
        store.draft = String(before) + "@" + replacement
    }

    // MARK: Attachments

    var trayItems: [ComposerAttachmentItem] {
        attachmentStore.items(for: store.agentId)
    }

    /// Hands the image to the tray: the pill appears at once in its `.decoding` phase while the
    /// decode/resize/encode pass runs off main (§6). A decode failure lands on the pill, retryable.
    func attachImageData(_ data: Data, fileName: String) {
        attachmentStore.addImage(
            data: data, fileName: fileName, to: store.agentId, store: store)
    }

    /// Attaches files picked in Files. Each pill appears at once in the `.decoding` phase (which
    /// also holds Send) and its bytes are read off the main actor
    /// (`ComposerAttachmentStore.addFile`): `Data(contentsOf:)` here froze the composer for the
    /// length of the read, which for an iCloud file is a download.
    func attachFileURLs(_ urls: [URL]) {
        for url in urls {
            attachmentStore.addFile(url: url, to: store.agentId, store: store)
        }
    }

    /// The add menu's "Paste image" (upstream en.ts:157; failure copy en.ts:184).
    func pasteImageFromClipboard() {
        guard let image = UIPasteboard.general.image,
            let data = image.jpegData(compressionQuality: 1.0)
        else {
            showToast("Failed to paste image")
            return
        }
        attachImageData(data, fileName: "pasted-\(UUID().uuidString.prefix(8)).jpg")
    }

    func retryAttachment(_ itemId: UUID) {
        attachmentStore.retry(itemId, in: store.agentId, store: store)
    }

    func removeAttachment(_ itemId: UUID) {
        attachmentStore.remove(itemId, from: store.agentId, store: store)
    }

    // MARK: Markdown and images

    func handleMarkdown(_ action: MarkdownAction) {
        switch action {
        case .openLink(let url):
            openURLFromEnvironment?(url)
        case .copyCode(let code):
            Clipboard.copy(code)
            Haptics.light()
            showToast("Code copied")
        case .image(let image):
            // `![alt](url)` inside a sentence renders as one link-styled run (a thumbnail
            // would reflow the line), so tapping it is the only way to see the picture.
            presentInlineImage(image)
        default:
            break
        }
    }

    /// Opens an inline prose image full screen through the same loader the cards use. A workspace
    /// path is read first (cached, off main); a remote one is the viewer's own job.
    private func presentInlineImage(_ image: MarkdownImage) {
        let remote = ["http://", "https://", "data:", "blob:"].contains {
            image.source.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().hasPrefix($0)
        }
        if remote {
            inlineImage = InlineProseImage(markdown: image, uiImage: nil)
            return
        }
        let path = image.source.hasPrefix("file://")
            ? (URL(string: image.source)?.path ?? image.source) : image.source
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let loaded = await self.loadImage(path: path) else {
                self.showToast("Couldn't read that image.")
                return
            }
            self.inlineImage = InlineProseImage(markdown: image, uiImage: loaded)
        }
    }

    /// Set by `ChatScreen` from `@Environment(\.openURL)`.
    var openURLFromEnvironment: ((URL) -> Void)?

    /// Reads an inline image through `WorkspaceFiles.fetch` (never `read`, which writes the Files
    /// page's visible state) and decodes it off main at display resolution. Cached by
    /// `(workspaceId, path)`.
    func loadImage(path: String) async -> UIImage? {
        guard let agent = store.agent, let workspaceId = agent.workspaceId,
            let descriptor = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        let key = "\(workspaceId)\u{0}\(path)" as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        let checkout = session.checkout(for: descriptor)
        guard let file = try? await checkout.files.fetch(path, maxBytes: 8 * 1024 * 1024),
            file.kind == .image, file.encoding == .base64, let content = file.content,
            let data = Data(base64Encoded: content)
        else { return nil }
        let maxPixel = Double(screenWidth * displayScale)
        let image = await Task.detached(priority: .userInitiated) {
            ComposerImageProcessor.thumbnail(data: data, maxPixelSize: maxPixel)
        }.value
        guard let image else { return nil }
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        imageCache.setObject(image, forKey: key, cost: Int(max(pixels, 1) * 4))
        return image
    }

    /// The scale of the screen this conversation is on, injected by `ChatScreen` from
    /// `@Environment(\.displayScale)`.
    var displayScale: CGFloat = 2

    /// A phone's width in points, for the rare case where no window scene is attached (previews,
    /// a scene-less snapshot).
    private static let fallbackScreenWidth: CGFloat = 430

    /// The width of the screen we are on, in points. `UIScreen.main` is deprecated on iOS 26, so
    /// the screen comes from the attached window scene (D1 §4).
    private var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let width = scene?.screen.bounds.width, width > 0 else {
            return Self.fallbackScreenWidth
        }
        return width
    }



    // MARK: Outline and end-of-transcript requests

    /// The chat outline: the daemon's prompt index when the host serves it (the whole
    /// conversation, loaded or not), otherwise the loaded turns. Never pages history in.
    var outlineItems: [ChatOutlineItem] {
        let indexed = store.promptOutline.prompts
        if store.promptOutline.isSupported, !indexed.isEmpty {
            return indexed.map { ChatOutlineItem(seq: $0.seq, preview: $0.preview) }
        }
        return store.turns.compactMap { turn in
            guard let row = turn.userMessage, case .userMessage(let message) = row.item else {
                return nil
            }
            return ChatOutlineItem(
                seq: row.seqStart, preview: PromptOutline.previewText(message.text))
        }
    }

    /// "Jump to message…" is offered once the conversation has enough prompts for the rail.
    var outlineAvailable: Bool {
        outlineItems.count >= ChatOutlineRail.minimumPrompts
    }

    /// The newest prompt's sequence, without building the outline. The reading-position report
    /// runs during a scroll, so it must not map every turn into a list (R-1); this stops at the
    /// first (newest) turn that carries a user message.
    var lastPromptSeq: Int? {
        if store.promptOutline.isSupported, let last = store.promptOutline.prompts.last {
            return last.seq
        }
        for turn in store.turns.reversed() {
            guard let row = turn.userMessage, case .userMessage = row.item else { continue }
            return row.seqStart
        }
        return nil
    }

    /// Bumped when the composer focuses: a *wish* to be at the end. The transcript glides only
    /// when the reader is within a screen of it; further up, the reading position wins and
    /// "Back to the end" offers the way back (H2 §2).
    var endScrollRequest = 0
    /// Bumped by "Back to the end": always goes, whatever the distance (H2 §2).
    var jumpToEndRequest = 0
    /// Bumped when the transcript is tapped: the composer drops focus (it owns the field).
    var dismissKeyboardRequest = 0

    func requestEndScroll() {
        endScrollRequest += 1
    }

    /// "Back to the end" (D1 §3): follow comes back at once and the transcript glides there, so
    /// the button leaves the screen on touch-down instead of fading out under the finger.
    func returnToEnd() {
        anchoringToAnswer = false
        isFollowing = true
        showsBackToEnd = false
        jumpToEndRequest += 1
    }

    func dismissKeyboard() {
        dismissKeyboardRequest += 1
    }

    // MARK: Environment

    /// The system's Reduce Motion, injected by `ChatScreen` (the controller has no environment).
    var reduceMotion = false

    /// The intercepted openURL action: `paseo-file` links open the workspace file viewer
    /// (absolute paths made workspace-relative); everything else falls through to the host.
    func fileLinkAction(host: OpenURLAction) -> OpenURLAction {
        OpenURLAction { [weak self] url in
            guard let self else { return .systemAction }
            // Prose hands non-link interactions back as `claude-markdown://presentation/…`
            // (SwiftUI `Text` links go through here, the UITextView path decodes them itself).
            // Without this an inline image tap reached the system and did nothing.
            if let action = MarkdownAction.decodePresentationURL(url) {
                self.handleMarkdown(action)
                return .handled
            }
            if let path = FilePathLinks.path(from: url) {
                self.openFileViewer(at: self.fileLinkDisplayPath(path))
                return .handled
            }
            host(url)
            return .handled
        }
    }

    /// A paseo-file target as the viewer wants it: leading `@` stripped; absolute paths under the
    /// agent's workspace become workspace-relative.
    func fileLinkDisplayPath(_ raw: String) -> String {
        let stripped = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        guard stripped.hasPrefix("/"),
            let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return stripped }
        return WorkspaceFileFormat.relativePath(stripped, cwd: workspace.cwd)
    }
}

/// The pipeline registration ticket: workspace id plus the token that owns the entry.
/// Written once, read in `deinit`. `Mutex`-guarded (the codebase's lock) so the box is
/// `Sendable` without isolation acrobatics.
final class DaemonFetchRegistration: @unchecked Sendable {
    private let state = Mutex<(workspaceID: String?, token: UUID?)>((nil, nil))

    func retain(workspaceID: String? = nil, token: UUID? = nil) {
        state.withLock {
            if let workspaceID { $0.workspaceID = workspaceID }
            if let token { $0.token = token }
        }
    }

    func snapshot() -> (workspaceID: String?, token: UUID?) {
        state.withLock { $0 }
    }
}

#endif
