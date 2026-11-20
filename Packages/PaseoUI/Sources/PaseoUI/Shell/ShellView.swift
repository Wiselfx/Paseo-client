#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One-shot signal from the shell into the composer to take keyboard focus. A Binding so the
/// composer can reset it after consuming. Internal so the composer can see it.
extension EnvironmentValues {
    @Entry var composerFocusRequested: Binding<Bool> = .constant(false)
}
/// The app after connecting: a drawer of workspaces and their agents on the left, the selected
/// agent's conversation in the middle, and the workspace panel pushed over both from the right
/// edge. The three surfaces are `UIView`s inside one UIKit container (`ShellContainer`), which
/// owns the drag, the settle and the material; this view owns the routing and builds the three
/// SwiftUI roots (R5 §1, §4).
public struct ShellView: View {
    let session: HostSession
    var onDisconnect: () -> Void
    /// A notification tap waiting to be routed. The app owns the value; the shell consumes it
    /// once the conversation selection exists (including after a cold launch).
    @Binding private var notificationTarget: AttentionTarget?
    /// A `paseo://` navigation link waiting to be routed (M20). Same one-shot contract as
    /// `notificationTarget`: `RootView` hands it over, the shell routes it and clears it.
    @Binding private var deepLinkTarget: DeepLink?

    @State private var selectedAgentId: String?
    @State private var conversation: ConversationStore?
    /// The draft session (UX-SPEC §3): shown while no agent is selected and after every "New
    /// session" entry point. One slot, like one draft tab.
    @State private var draft: DraftSession?
    /// True when the draft was opened from an entry point rather than by the idle shell, so a
    /// late agent list never yanks it away from someone who is typing.
    @State private var draftOpenedByUser = false
    /// A terminal to open the panel on, from a notification tap; cleared when the panel closes.
    @State private var panelTerminalId: String?
    /// Set by a deep link's `open-project` route; the sidebar presents its Add project sheet.
    @State private var addProjectRequested = false
    @State private var composerFocusRequested = false
    /// The drawer bridge. A class held by `@State`: the container moves the surfaces, so nothing
    /// here changes while a finger is down.
    @State private var drawer = ShellDrawer()
    @State private var toastCenter = ToastCenter()
    /// False until the first `onAppear` has picked the agent or created the draft: the first
    /// frame is the launch skeleton, never a home greeting that is then replaced (E2 §3.3).
    @State private var homeSettled = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codeSizeStep) private var codeSizeStep
    @Environment(\.pureBlack) private var pureBlack
    @Environment(\.accent) private var accent
    @Environment(\.hostSwitch) private var hostSwitch
    @Environment(\.notificationPermissionAction) private var requestNotificationPermission
    @Environment(\.notificationTestAction) private var notificationTestAction

    public init(
        session: HostSession, onDisconnect: @escaping () -> Void,
        notificationTarget: Binding<AttentionTarget?> = .constant(nil),
        deepLinkTarget: Binding<DeepLink?> = .constant(nil)
    ) {
        self.session = session
        self.onDisconnect = onDisconnect
        _notificationTarget = notificationTarget
        _deepLinkTarget = deepLinkTarget
    }

    public var body: some View {
        let _ = PaseoPerf.body("Shell")
        let _ = PaseoPerf.why(Self.self)
        ShellContainer(
            drawer: drawer, rootsKey: rootsKey, sidebar: sidebar, main: main, panel: panel)
            .ignoresSafeArea()
            .toastHost(toastCenter)
            .background {
                ShellSessionWatcher(
                    session: session,
                    onAgentsChange: adoptAgents,
                    onDirectoryLoaded: directoryLoaded)
                ConnectionStatusToast(session: session, toast: toastCenter)
                if PaseoPerf.enabled {
                    ShellPerfProbes(session: session, conversation: conversation)
                }
            }
            .onAppear {
                drawer.onNewSession = { openNewSession(workspaceId: nil) }
                session.hostSettings.startPresence(
                    focusedAgentId: selectedAgentId, appVisible: scenePhase == .active)
                session.attention.setFocusedAgent(scenePhase == .active ? selectedAgentId : nil)
                restoreStartupScreen()
                ComposerWarmup.scheduleOnce()
                handleNotificationTarget()
                handleDeepLinkTarget()
                homeSettled = true
            }
            .onDisappear {
                session.hostSettings.stopPresence()
                session.attention.setFocusedAgent(nil)
            }
            .onChange(of: selectedAgentId) { _, id in
                session.hostSettings.updateFocus(id)
                session.attention.setFocusedAgent(scenePhase == .active ? id : nil)
            }
            .onChange(of: scenePhase) { _, phase in
                session.hostSettings.updateVisibility(phase == .active)
                session.attention.setFocusedAgent(phase == .active ? selectedAgentId : nil)
                // The screen it reopens on is the one that was on screen when the app left.
                if phase == .background { rememberScreen() }
            }
            .onChange(of: notificationTarget) { _, _ in
                handleNotificationTarget()
            }
            .onChange(of: draft?.workspaceId) { _, _ in
                // Moving the draft to another workspace changes the screen to reopen.
                rememberScreen()
            }
            .onChange(of: deepLinkTarget) { _, _ in
                handleDeepLinkTarget()
            }
    }

    // MARK: Roots

    /// A root as the container hosts it: the environment SwiftUI set outside the shell is not
    /// inherited by a `UIHostingController`, so every value the subtrees read is re-applied here
    /// (R5 §1).
    private func root<Content: View>(_ content: Content) -> AnyView {
        AnyView(
            content
                .environment(\.shellDrawer, drawer)
                .environment(\.toast, toastCenter)
                .environment(\.hostSwitch, hostSwitch)
                .environment(\.codeSizeStep, codeSizeStep)
                .environment(\.pureBlack, pureBlack)
                // Same reason as `pureBlack`: a hosting controller built inside the shell does
                // not inherit the app's SwiftUI environment, so the accent must be re-applied to
                // every subtree or the bridged trait would write its default (E2 §2.2).
                .environment(\.accent, accent)
                .environment(\.notificationPermissionAction, requestNotificationPermission)
                .environment(\.notificationTestAction, notificationTestAction)
                .dynamicTypeSize(dynamicTypeSize)
                .foregroundStyle(Palette.ink)
                .tint(Palette.ink)
        )
    }

    /// Everything the three roots are built from that can differ between two passes of this body.
    /// The container assigns new roots only when this changes (W1): the body also runs when an
    /// environment closure the app re-creates (`notificationPermissionAction`) or a binding counts as
    /// changed, which re-assigned all three hosting controllers' roots and re-ran the whole sidebar,
    /// the chat screen and the composer at the first keyboard focus (about 220 ms in Release). The
    /// closures the roots capture act on `@State` storage and stable objects, so an unchanged key
    /// means the old roots are still right.
    private var rootsKey: ShellRootsKey {
        ShellRootsKey(
            session: ObjectIdentifier(session), selectedAgentId: selectedAgentId,
            conversation: conversation.map { ObjectIdentifier($0) },
            draft: draft.map { ObjectIdentifier($0) }, homeSettled: homeSettled,
            panelTerminalId: panelTerminalId, workspaceId: currentWorkspaceId,
            directoryLoaded: session.workspaceDirectory.hasLoaded,
            directoryFailed: session.workspaceDirectory.error != nil,
            dynamicTypeSize: dynamicTypeSize, reduceMotion: reduceMotion,
            codeSizeStep: codeSizeStep, pureBlack: pureBlack, accent: accent,
            hostSwitch: hostSwitch.map { ObjectIdentifier($0) })
    }

    private var sidebar: AnyView {
        root(
            PaseoSidebar(
                session: session,
                selectedAgentId: selectedAgentId,
                onSelectAgent: { select($0) },
                onNewSession: { openNewSession(workspaceId: $0) },
                onNewAgent: { openNewAgent(workspace: $0) },
                currentWorkspaceId: currentWorkspaceId,
                onDisconnect: onDisconnect,
                onTogglePanel: { drawer.toggle(.panel) },
                addProjectRequest: $addProjectRequested))
    }

    private var main: AnyView {
        root(
            VStack(spacing: 0) {
                if let conversation {
                    ClaudeChatView(
                        session: session,
                        store: conversation,
                        onOpenSidebar: { drawer.toggle(.sidebar) },
                        onOpenPanel: { drawer.open(.panel) },
                        onNewAgent: { prompt in openNewAgent(prompt: prompt) },
                        onForkAgent: { agentId in select(agentId) },
                        onOpenAgent: { agentId in select(agentId) }
                    )
                    .id(conversation.agentId)
                } else if let draft {
                    DraftChatView(
                        session: session,
                        draft: draft,
                        onOpenSidebar: { drawer.toggle(.sidebar) },
                        onOpenPanel: { drawer.open(.panel) },
                        onAddProject: {
                            addProjectRequested = true
                            drawer.open(.sidebar)
                        },
                        onSubmit: { submission in submitDraft(submission) }
                    )
                    // The draft's own id is the view's identity: focus and attachment tray never
                    // leak from one draft to another, and a restored draft keeps its identity.
                    .id(draft.draftId)
                } else if !homeSettled
                    || (!session.workspaceDirectory.hasLoaded
                        && session.workspaceDirectory.error == nil)
                {
                    // Still deciding between a chat and a draft: the launch frame stays up. A
                    // home greeting must never appear and then be replaced by the same greeting
                    // on the very next frame (E2 §3.3).
                    LaunchSkeleton()
                } else {
                    EmptyMain(session: session, onOpenSidebar: { drawer.toggle(.sidebar) })
                }
            }
            .environment(\.composerFocusRequested, $composerFocusRequested))
    }

    private var panel: AnyView {
        root(
            PanelRoot(
                session: session,
                workspaceId: currentWorkspaceId,
                currentAgentId: selectedAgentId,
                initialTerminalId: panelTerminalId,
                onSelectAgent: { id in
                    select(id)
                    drawer.close()
                },
                onNewAgent: { workspace in
                    openNewAgent(workspace: workspace)
                    drawer.close()
                },
                onMentionInChat: mentionInChat
            )
            // Per-workspace identity: the panel's tab is stored per workspace, and a workspace
            // switch must load that workspace's own remembered tab. Closing and reopening the
            // same workspace keeps the identity, so the tab and scroll position survive.
            .id(currentWorkspaceId ?? "none"))
    }

    /// Both the panel and "mention in chat" follow the workspace on screen, conversation or
    /// draft (audit C #1).
    private var currentWorkspaceId: String? {
        conversation?.workspaceId ?? draft?.workspaceId
    }

    // MARK: Mention in chat

    /// Appends `@relative/path ` to the open conversation's draft (space-separated), or to the
    /// draft session when that is what is on screen; closes the panel and focuses the composer.
    private func mentionInChat(_ relPath: String) {
        let mention = "@\(relPath) "
        if let store = conversation {
            store.draft = appending(mention, to: store.draft)
        } else if let draft {
            draft.text = appending(mention, to: draft.text)
        }
        drawer.close()
        composerFocusRequested = true
        Haptics.light()
    }

    private func appending(_ mention: String, to text: String) -> String {
        if text.isEmpty { return mention }
        if text.hasSuffix(" ") || text.hasSuffix("\n") { return text + mention }
        return text + " " + mention
    }

    // MARK: Reactions

    /// The agent list changed (an agent was archived, or one arrived while the shell was idle).
    /// Runs outside `body`, so the shell never observes the list itself (R5 §4.1).
    private func adoptAgents() {
        let agents = session.agents
        if let selectedAgentId {
            if !agents.contains(where: { $0.id == selectedAgentId }) {
                conversation = nil
                self.selectedAgentId = nil
                if let first = agents.first { select(first.id, closeDrawer: false) }
            }
        } else if let first = agents.first, !draftOpenedByUser, draftIsUntouched {
            // An empty shell adopts the newest agent; a draft someone opened — or has already
            // typed into — stays.
            select(first.id, closeDrawer: false)
        }
        showDefaultDraftIfIdle()
        // The agent list also carries the workspace a conversation lives in; the screen record
        // learns it as soon as it is known.
        rememberScreen()
    }

    // MARK: Selection

    /// Routes a notification tap through the same selection path the sidebar uses. Agent targets
    /// ignore their workspace hint (the agent can move); terminal targets pick the newest agent
    /// in the terminal's workspace and open the workspace panel.
    private func handleNotificationTarget() {
        guard let target = notificationTarget else { return }
        notificationTarget = nil
        drawer.close()
        switch target.kind {
        case .agent:
            guard let agentId = target.agentId else { return }
            select(agentId)
        case .terminal:
            let workspaceId =
                target.workspaceId
                ?? target.terminalId.flatMap { session.terminals.workspaceId(forTerminal: $0) }
            guard let workspaceId,
                let agent = session.agents.first(where: { $0.workspaceId == workspaceId })
            else { return }
            panelTerminalId = target.terminalId
            select(agent.id)
            drawer.open(.panel)
        }
    }

    /// Routes one `paseo://` navigation link through the same selection path the sidebar uses.
    /// Agent links select the agent (its conversation loads the snapshot, so a stale list entry
    /// is not required). Workspace links pick the workspace's newest agent; a terminal intent
    /// also opens the workspace panel on that terminal, exactly like a terminal notification tap.
    /// `open-project` opens the sidebar's Add project sheet; host root keeps the current agent.
    private func handleDeepLinkTarget() {
        guard let link = deepLinkTarget else { return }
        deepLinkTarget = nil

        switch link {
        case .agent(_, let agentId):
            drawer.close()
            select(agentId)
        case .workspace(_, let workspaceId, let open):
            drawer.close()
            if case .agent(let agentId) = open {
                select(agentId)
                return
            }
            guard let agent = session.agents.first(where: { $0.workspaceId == workspaceId }) else {
                // No agent to show yet: the workspace still exists in the sidebar.
                drawer.open(.sidebar)
                return
            }
            select(agent.id, closeDrawer: false)
            if case .terminal(let terminalId) = open {
                panelTerminalId = terminalId
                drawer.open(.panel)
            }
        case .host:
            drawer.close()
            if selectedAgentId == nil, let first = session.agents.first { select(first.id) }
        case .openProject:
            addProjectRequested = true
            drawer.open(.sidebar)
        case .newAgent(_, let workspaceID):
            // The intent's draft: create it in the workspace (or the most recent
            // one) and focus its composer through the existing focus request —
            // the draft's `ComposerView` consumes and resets it. Creation stays
            // user-driven: the intent never sends.
            drawer.close()
            openNewSession(workspaceId: workspaceID)
            composerFocusRequested = true
        case .offer, .unsupported:
            // Offers go through RootView's pairing sheet; unsupported routes get a message there.
            break
        }
    }

    private func select(_ agentId: String, closeDrawer: Bool = true) {
        // Picking an agent always leaves the draft, even when it is the agent the sidebar still
        // shows selected: the row is the way back to the conversation.
        dropDraft()
        if selectedAgentId != agentId {
            selectedAgentId = agentId
            conversation = session.conversation(for: agentId)
            let store = conversation
            Task {
                // Opening clears the badge on the daemon; refresh so the sidebar row agrees.
                guard store?.agent?.requiresAttention == true else { return }
                await store?.clearAttention()
                await session.refreshAgents()
            }
        }
        if closeDrawer, drawer.state == .sidebar { drawer.close() }
        rememberScreen()
    }

    // MARK: Startup

    /// Reopens the screen the app was left on: the last workspace and its tab — a conversation
    /// or an unsent new-session draft. Restore follows what was last opened, never the
    /// connection state; a host that is still connecting or offline keeps the target.
    /// `Upstream: docs/expo-router.md:37-45`,
    /// `packages/app/src/navigation/host-runtime-bootstrap.ts:141-171`.
    private func restoreStartupScreen() {
        guard selectedAgentId == nil, draft == nil else { return }
        guard let last = DraftStore.shared.lastScreen else {
            openStartupFallback()
            return
        }
        // Another host's screen: this host starts as it always did.
        if let hostId = last.hostId, let current = session.serverInfo?.serverId, hostId != current {
            openStartupFallback()
            return
        }
        // The remembered workspace is proven gone once the directory has loaded.
        if let workspaceId = last.workspaceId, session.workspaceDirectory.hasLoaded,
            session.workspaceDirectory.workspace(id: workspaceId) == nil
        {
            openStartupFallback()
            return
        }
        if let agentId = last.agentId {
            // A conversation loads its own snapshot, so a not-yet-listed agent is still restored.
            // An agent that left the list after it loaded is gone: the fallback takes over.
            if !session.agents.isEmpty, !session.agents.contains(where: { $0.id == agentId }) {
                openStartupFallback()
                return
            }
            select(agentId, closeDrawer: false)
            return
        }
        if let draftId = last.draftId {
            restoreDraft(workspaceId: last.workspaceId, draftId: draftId)
            return
        }
        openStartupFallback()
    }

    /// What launch does when there is nothing to restore, or the remembered screen is gone.
    private func openStartupFallback() {
        if let first = session.agents.first { select(first.id, closeDrawer: false) }
        showDefaultDraftIfIdle()
    }

    /// Puts back the unsent new-session draft, workspace id included: the directory may still be
    /// loading, so the draft keeps the remembered id and picks up its `cwd` once the workspace is
    /// known (`directoryLoaded`).
    private func restoreDraft(workspaceId: String?, draftId: String) {
        let workspace = workspaceId.flatMap { session.workspaceDirectory.workspace(id: $0) }
        drawer.close()
        selectedAgentId = nil
        conversation = nil
        // A restored screen is the user's: a late agent list must not yank them to a chat.
        draftOpenedByUser = true
        draft = DraftSession(
            workspaceId: workspaceId, cwd: workspace?.cwd ?? "",
            preferences: DraftStore.shared.formPreferences.draftPreferences, draftId: draftId,
            drafts: .shared)
        rememberScreen()
    }

    /// The directory has loaded: a restored draft learns its workspace's `cwd`, and a draft whose
    /// workspace turned out to be gone falls back to today's launch screen.
    private func directoryLoaded() {
        if selectedAgentId == nil, draft == nil {
            restoreStartupScreen()
            return
        }
        if let draft, let workspaceId = draft.workspaceId {
            if let workspace = session.workspaceDirectory.workspace(id: workspaceId) {
                if draft.cwd.isEmpty {
                    draft.move(toWorkspace: workspace.id, cwd: workspace.cwd)
                }
            } else if draft.pendingPrompt == nil, draft.text.isEmpty {
                dropDraft()
                openStartupFallback()
                return
            }
        }
        showDefaultDraftIfIdle()
        rememberScreen()
    }

    // MARK: Last screen

    /// Keeps the screen that is on screen, so the next launch reopens it. Writes only when it
    /// changed (the store compares the record).
    /// `Upstream: packages/app/src/stores/last-workspace-selection.ts:50-63`.
    private func rememberScreen() {
        let screen: LastScreen
        if let conversation {
            let workspaceId =
                conversation.agent?.workspaceId
                ?? session.agents.first { $0.id == conversation.agentId }?.workspaceId
            screen = LastScreen(
                hostId: session.serverInfo?.serverId, workspaceId: workspaceId,
                agentId: conversation.agentId)
        } else if let draft {
            // A draft that is creating its agent is not a screen to reopen.
            guard draft.pendingPrompt == nil else { return }
            screen = LastScreen(
                hostId: session.serverInfo?.serverId, workspaceId: draft.workspaceId,
                draftId: draft.draftId)
        } else {
            return
        }
        DraftStore.shared.remember(screen)
    }

    // MARK: Drafts

    /// The draft system's one entry point: the sidebar's "New session" pill and each workspace's
    /// `+` (both `onNewSession(workspaceId:)`), the panel's Agents tab, the composer's menu, the
    /// command center and the deep links all land here.
    private func openNewSession(workspaceId: String?, userInitiated: Bool = true) {
        let directory = session.workspaceDirectory
        let onScreen = conversation?.agent?.workspaceId
        let resolved =
            workspaceId.flatMap { directory.workspace(id: $0) }
            ?? onScreen.flatMap { directory.workspace(id: $0) }
            ?? mostRecentWorkspace
        if userInitiated { draftOpenedByUser = true }
        drawer.close()
        // A new session is not the agent that was on screen: the draft replaces the chat, and
        // the sidebar stops marking a row as current.
        selectedAgentId = nil
        conversation = nil
        if let current = draft, current.workspaceId == resolved?.id,
            current.pendingPrompt == nil
        {
            return
        }
        let preferences =
            draft?.preferences ?? DraftStore.shared.formPreferences.draftPreferences
        // No workspace at all: the draft's hero offers "Add project" instead of a composer
        // (§2.2), so there is still somewhere to go.
        draft = DraftSession(
            workspaceId: resolved?.id, cwd: resolved?.cwd ?? "", preferences: preferences,
            drafts: .shared)
        rememberScreen()
    }

    /// The workspace with the newest activity, for “New session” with no conversation on
    /// screen (§2.2).
    private var mostRecentWorkspace: WorkspaceDescriptor? {
        func stamp(_ workspace: WorkspaceDescriptor) -> Date {
            for value in [workspace.activityAt, workspace.lastUserMessageAt, workspace.createdAt] {
                if let value, let date = PaseoDate.parse(value) { return date }
            }
            return .distantPast
        }
        return session.workspaceDirectory.workspaces.max { stamp($0) < stamp($1) }
    }

    /// "New agent" in a conversation's menu: the typed text moves into the draft rather than
    /// being copied, so the conversation it came from is left empty.
    private func openNewAgent(prompt: String) {
        let from = conversation
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        openNewSession(workspaceId: from?.agent?.workspaceId)
        guard !trimmed.isEmpty else { return }
        if let current = draft, current.text.isEmpty { current.text = prompt }
        if from?.draft.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            from?.draft = ""
        }
    }

    private func openNewAgent(workspace: WorkspaceDescriptor) {
        openNewSession(workspaceId: workspace.id)
    }

    // MARK: Draft creation

    /// The draft's send, owned by the shell (D2 §3): creation outlives the composer, which is
    /// destroyed by the swap, so no `@State` of a dying view is written after an `await`.
    private func submitDraft(_ submission: DraftSubmission) {
        guard let draft, !submission.isEmpty else { return }
        Task { await createAgent(from: draft, submission: submission) }
    }

    /// Creates the agent, then shows its conversation. `select` builds the conversation store on
    /// its own, so this never waits on `refreshAgents` (the agent update arrives on the
    /// subscription) and never polls: `DraftSession.create` has already cleared the pending
    /// bubble when it returns, so any wait here would flash the draft's hero before the swap.
    private func createAgent(from draft: DraftSession, submission: DraftSubmission) async {
        let session = self.session
        guard
            let agentId = await draft.create(
                using: session.agentControl, attachments: submission.attachments)
        else {
            // The draft stays: `error` shows inline and the composer restores its tray.
            return
        }
        // The agent exists: the draft is spent whether or not its screen is still the one on
        // show (upstream clears the draft's input on create success).
        draft.markSent()
        // The user may have opened something else while the create was in flight; their screen
        // wins over this draft's.
        guard self.draft === draft else { return }
        withAnimation(Motion.fade.resolved(reduceMotion: reduceMotion)) {
            select(agentId)
        }
    }

    /// True when there is no draft, or one nobody has touched yet: the idle shell may still
    /// adopt an arriving agent in that case.
    private var draftIsUntouched: Bool {
        guard let draft else { return true }
        return !draft.isCreating && draft.pendingPrompt == nil
            && draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// No agent on screen and the directory is known: show the draft for the workspace that was
    /// last in use, as Claude's home does.
    private func showDefaultDraftIfIdle() {
        guard selectedAgentId == nil, draft == nil, session.workspaceDirectory.hasLoaded else {
            return
        }
        openNewSession(workspaceId: nil, userInitiated: false)
    }

    private func dropDraft() {
        draft = nil
        draftOpenedByUser = false
    }
}
/// The same shell, under the name the app has always used.
public typealias PaseoShellView = ShellView
#endif
