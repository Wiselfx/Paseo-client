#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One-shot signal from the shell into the composer to take keyboard focus. A Binding so the
/// composer can reset it after consuming. Internal so the composer can see it.
struct ComposerFocusKey: EnvironmentKey {
    static var defaultValue: Binding<Bool> { .constant(false) }
}

extension EnvironmentValues {
    var composerFocusRequested: Binding<Bool> {
        get { self[ComposerFocusKey.self] }
        set { self[ComposerFocusKey.self] = newValue }
    }
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
    /// Rebuilds the draft's view when the slot is filled with a different draft, so its focus and
    /// attachment tray never leak from one workspace to another.
    @State private var draftId = UUID()
    /// The last settings picked in a draft, for the next one on this host (§3.1).
    @State private var lastDraftPreferences = DraftPreferences()
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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codeSizeStep) private var codeSizeStep
    @Environment(\.pureBlack) private var pureBlack
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
        ShellContainer(drawer: drawer, sidebar: sidebar, main: main, panel: panel)
            .ignoresSafeArea()
            .toastHost(toastCenter)
            .background {
                ShellSessionWatcher(
                    session: session,
                    onAgentsChange: adoptAgents,
                    onDirectoryLoaded: showDefaultDraftIfIdle)
            }
            .onAppear {
                drawer.onNewSession = { openNewSession(workspaceId: nil) }
                session.hostSettings.startPresence(
                    focusedAgentId: selectedAgentId, appVisible: scenePhase == .active)
                session.attention.setFocusedAgent(scenePhase == .active ? selectedAgentId : nil)
                if selectedAgentId == nil, let first = session.agents.first {
                    select(first.id, closeDrawer: false)
                }
                showDefaultDraftIfIdle()
                handleNotificationTarget()
                handleDeepLinkTarget()
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
            }
            .onChange(of: notificationTarget) { _, _ in
                handleNotificationTarget()
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
                .environment(\.notificationPermissionAction, requestNotificationPermission)
                .environment(\.notificationTestAction, notificationTestAction)
                .dynamicTypeSize(dynamicTypeSize)
                .foregroundStyle(Palette.ink)
                .tint(Palette.ink)
        )
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
                ConnectionBanner(session: session, onDisconnect: onDisconnect)
                if let conversation {
                    ClaudeChatView(
                        session: session,
                        store: conversation,
                        onOpenSidebar: { drawer.open(.sidebar) },
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
                        onOpenSidebar: { drawer.open(.sidebar) },
                        onOpenPanel: { drawer.open(.panel) },
                        onAddProject: {
                            addProjectRequested = true
                            drawer.open(.sidebar)
                        },
                        onSubmit: { submission in submitDraft(submission) }
                    )
                    .id(draftId)
                } else {
                    EmptyMain(session: session, onOpenSidebar: { drawer.open(.sidebar) })
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
        conversation?.agent?.workspaceId ?? draft?.workspaceId
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
        Haptics.selection()
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
        let preferences = draft?.preferences ?? lastDraftPreferences
        if let current = draft { lastDraftPreferences = current.preferences }
        // No workspace at all: the draft's hero offers "Add project" instead of a composer
        // (§2.2), so there is still somewhere to go.
        draft = DraftSession(
            workspaceId: resolved?.id, cwd: resolved?.cwd ?? "", preferences: preferences)
        draftId = UUID()
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
        if let draft { lastDraftPreferences = draft.preferences }
        draft = nil
        draftOpenedByUser = false
    }
}

/// The same shell, under the name the app has always used.
public typealias PaseoShellView = ShellView

/// Watches the two session facts the shell reacts to, in its own body, so `ShellView.body` never
/// reads the agent list or the directory state (R5 §4.1). It reacts to the agent ids, not to
/// every snapshot field, so a status change does not re-route anything.
struct ShellSessionWatcher: View {
    let session: HostSession
    let onAgentsChange: () -> Void
    let onDirectoryLoaded: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.agents.map(\.id)) { _, _ in
                onAgentsChange()
            }
            .onChange(of: session.workspaceDirectory.hasLoaded) { _, loaded in
                if loaded { onDirectoryLoaded() }
            }
    }
}

/// The one connection banner: the chat, the draft and the empty main all show it, below the
/// status bar (audit C #2). It observes the connection in its own body.
struct ConnectionBanner: View {
    let session: HostSession
    let onDisconnect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        switch session.connection {
        case .reconnecting, .failed: true
        case .idle, .connecting, .connected: false
        }
    }

    var body: some View {
        Group {
            if isVisible { banner }
        }
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: isVisible)
    }

    @ViewBuilder private var banner: some View {
        switch session.connection {
        case .reconnecting:
            InlineBanner(.info, title: "Reconnecting…")
                .overlay(alignment: .trailing) {
                    InlineProgress().padding(.trailing, Space.lg)
                }
        case .failed:
            InlineBanner(
                .failure,
                title: "Can't reach the host. Check that the daemon is running.",
                action: ("Disconnect", onDisconnect))
        case .idle, .connecting, .connected:
            EmptyView()
        }
    }
}

/// The panel's root: it resolves the workspace descriptor in its own body, so the shell body
/// never reads the directory (R5 §4.1).
struct PanelRoot: View {
    let session: HostSession
    let workspaceId: String?
    let currentAgentId: String?
    let initialTerminalId: String?
    let onSelectAgent: (String) -> Void
    let onNewAgent: (WorkspaceDescriptor) -> Void
    let onMentionInChat: (String) -> Void

    var body: some View {
        WorkspacePanel(
            session: session,
            workspace: workspaceId.flatMap { session.workspaceDirectory.workspace(id: $0) },
            currentAgentId: currentAgentId,
            onSelectAgent: onSelectAgent,
            onNewAgent: onNewAgent,
            onMentionInChat: onMentionInChat,
            initialTerminalId: initialTerminalId)
    }
}

/// No agent and no draft: the brand mark, and a retry when the agent list failed (R5 §4.4).
struct EmptyMain: View {
    let session: HostSession
    let onOpenSidebar: () -> Void

    private func refreshAgents() {
        Task { await session.refreshAgents() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ShellHeader(leading: .sidebar(onOpenSidebar)) {
                Color.clear
            } trailing: {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            ZStack {
                ClaudeHomeHero()
                if let error = session.agentsError {
                    VStack {
                        Spacer()
                        InlineBanner(
                            .failure, title: error, action: ("Try again", refreshAgents)
                        )
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, Space.xl)
                    }
                }
            }
        }
    }
}
#endif
