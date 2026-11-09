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
/// edge. Both edges share the `EdgeDrawer` physics; the surfaces track the finger, settle by
/// projected position, and keep the display's corner radius throughout.
public struct PaseoShellView: View {
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
    @State private var newAgentRequest: NewAgentRequest?
    @State private var isDrawerOpen = false
    @State private var drawerProgress: CGFloat = 0
    @State private var isPanelOpen = false
    @State private var panelProgress: CGFloat = 0
    /// A terminal to open the panel on, from a notification tap; cleared when the panel closes.
    @State private var panelTerminalId: String?
    /// Set by a deep link's `open-project` route; the sidebar presents its Add project sheet.
    @State private var addProjectRequested = false
    @State private var composerFocusRequested = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let drawerFraction: CGFloat = 0.82
    /// The panel is a full-width push, not a drawer (§1.3).
    private let panelFraction: CGFloat = 1
    /// How far the conversation slides left while the panel is up (§1.3).
    private let panelParallax: CGFloat = 0.3

    public init(
        session: HostSession, onDisconnect: @escaping () -> Void,
        notificationTarget: Binding<AttentionTarget?> = .constant(nil),
        deepLinkTarget: Binding<DeepLink?> = .constant(nil)
    ) {
        self.session = session
        self.onDisconnect = onDisconnect
        _notificationTarget = notificationTarget
        _deepLinkTarget = deepLinkTarget
        ClaudeFontResources.register()
    }

    public var body: some View {
        GeometryReader { geometry in
            shell(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .sheet(item: $newAgentRequest) { request in
            ClaudeNewAgentSheet(
                session: session,
                workspaceId: request.workspaceId,
                cwd: request.cwd,
                initialPrompt: request.prompt
            ) { agentId in
                if let prompt = request.trimmedPrompt, conversation?.draft.trimmingCharacters(
                    in: .whitespacesAndNewlines) == prompt
                {
                    conversation?.draft = ""
                }
                newAgentRequest = nil
                select(agentId)
            }
        }
        .onAppear {
            session.hostSettings.startPresence(
                focusedAgentId: selectedAgentId, appVisible: scenePhase == .active)
            session.attention.setFocusedAgent(scenePhase == .active ? selectedAgentId : nil)
            if selectedAgentId == nil, let first = session.agents.first { select(first.id, closeDrawer: false) }
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
        .onChange(of: session.agents) { _, agents in
            if let selectedAgentId {
                if !agents.contains(where: { $0.id == selectedAgentId }) {
                    conversation = nil
                    self.selectedAgentId = nil
                    if let first = agents.first { select(first.id, closeDrawer: false) }
                }
            } else if let first = agents.first {
                select(first.id, closeDrawer: false)
            }
        }
    }

    // MARK: Shell

    /// Three surfaces, one material (§1): the sidebar revealed underneath, the conversation card,
    /// and the workspace panel pushed over both. The canvas and both cards are full bleed — the
    /// status bar and the home indicator area always belong to whichever surface is on top — and
    /// the cards keep the display's corner radius at every point of the move.
    private func shell(width: CGFloat, height: CGFloat) -> some View {
        let drawerWidth = width * drawerFraction
        return ZStack(alignment: .leading) {
            // Sidebar canvas == conversation canvas (§1.1): only the hairline and the dim
            // separate the two surfaces.
            ClaudePalette.background.ignoresSafeArea()
            sidebarSurface(width: drawerWidth)
            conversationSurface(width: width, height: height, drawerWidth: drawerWidth)
            panelSurface(width: width, height: height)
        }
    }

    private func sidebarSurface(width: CGFloat) -> some View {
        PaseoSidebar(
            session: session,
            selectedAgentId: selectedAgentId,
            onSelectAgent: { select($0) },
            onNewSession: { openNewSession(workspaceId: $0) },
            onNewAgent: { openNewAgent(workspace: $0) },
            currentWorkspaceId: conversation?.agent?.workspaceId,
            onDisconnect: onDisconnect,
            onTogglePanel: { settlePanel(open: !isPanelOpen) },
            addProjectRequest: $addProjectRequested
        )
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func conversationSurface(width: CGFloat, height: CGFloat, drawerWidth: CGFloat)
        -> some View
    {
        let offset = drawerWidth * drawerProgress - width * panelParallax * panelProgress
        return main
            .frame(width: width, height: height)
            .background { EdgeDrawerCard() }
            .environment(\.composerFocusRequested, $composerFocusRequested)
            .overlay {
                EdgeDrawerDim(progress: max(drawerProgress, panelProgress), onTap: closeDrawers)
            }
            .overlay { EdgeDrawerHairline(progress: drawerProgress) }
            .offset(x: offset)
            .edgeDrawerDrag(
                edge: .leading, screenWidth: width, drawerWidth: drawerWidth,
                isOpen: isDrawerOpen, blocked: isPanelOpen,
                progress: $drawerProgress, onSettle: { settleDrawer(open: $0) })
            .edgeDrawerDrag(
                edge: .trailing, screenWidth: width, drawerWidth: width * panelFraction,
                isOpen: isPanelOpen, blocked: isDrawerOpen,
                progress: $panelProgress, onSettle: { settlePanel(open: $0) })
    }

    /// The panel stays mounted so its tab, its scroll position and its gesture state survive a
    /// close and reopen for the same workspace; it is off screen unless it is up (§1.3, §1.4).
    private func panelSurface(width: CGFloat, height: CGFloat) -> some View {
        WorkspacePanel(
            session: session,
            workspace: selectedWorkspace,
            currentAgentId: selectedAgentId,
            onSelectAgent: { id in
                select(id)
                settlePanel(open: false)
            },
            onNewAgent: { workspace in
                openNewAgent(workspace: workspace)
                settlePanel(open: false)
            },
            onMentionInChat: mentionInChat,
            initialTerminalId: panelTerminalId,
            onClose: { settlePanel(open: false) },
            dismissDrag: PanelDismissDrag(
                progress: $panelProgress, width: width,
                onSettle: { settlePanel(open: $0) })
        )
        // Per-workspace identity: the panel's tab is stored per workspace, and a workspace
        // switch must load that workspace's own remembered tab. Closing and reopening the same
        // workspace keeps the identity, so the tab and scroll position survive.
        .id(selectedWorkspace?.id ?? "none")
        .frame(width: width * panelFraction, height: height, alignment: .top)
        .background { EdgeDrawerCard() }
        .overlay { EdgeDrawerHairline(progress: panelProgress) }
        .offset(x: width * (1 - panelProgress))
        .edgeDrawerDrag(
            edge: .leading, screenWidth: width, drawerWidth: width,
            isOpen: isPanelOpen, blocked: isDrawerOpen, openDirection: .trailing,
            requiresEdgeZone: true,
            progress: $panelProgress, onSettle: { settlePanel(open: $0) })
        .accessibilityHidden(panelProgress == 0)
        .allowsHitTesting(panelProgress > 0)
    }

    // MARK: Main

    /// The offline/reconnecting banner, from the live `DaemonConnection` state (M14). Calm
    /// one-liners; the reconnect itself is the connection's own retry, not a second spinner
    /// system. A failed (gave-up) connection offers Disconnect back to the connect screen.
    @ViewBuilder private var connectionBanner: some View {
        switch session.connection {
        case .reconnecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(ClaudePalette.secondary)
                Text("Reconnecting…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(ClaudePalette.panel)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reconnecting")
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(ClaudePalette.failureInk)
                Text("Can't reach the host. Check that the daemon is running.")
                    .lineLimit(2)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudePalette.failureInk)
                Spacer(minLength: 8)
                Button("Disconnect") {
                    onDisconnect()
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .accessibilityIdentifier("shell.connection.disconnect")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(ClaudePalette.panel)
        case .idle, .connecting, .connected:
            EmptyView()
        }
    }

    @ViewBuilder private var main: some View {
        VStack(spacing: 0) {
            connectionBanner
            if let conversation {
            ClaudeChatView(
                session: session,
                store: conversation,
                onOpenSidebar: { settleDrawer(open: true) },
                onOpenPanel: { settlePanel(open: true) },
                onNewAgent: { prompt in openNewAgent(prompt: prompt) },
                onForkAgent: { agentId in select(agentId) },
                onOpenAgent: { agentId in select(agentId) }
            )
            .id(conversation.agentId)
        } else {
            emptyMain
        }
        }
    }

    private var emptyMain: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    settleDrawer(open: true)
                } label: {
                    UnequalMenu().stroke(
                        ClaudePalette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .frame(width: 18, height: 17)
                    .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open sidebar")
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            ZStack {
                ClaudeHomeHero(hint: "Pick a workspace from the sidebar to start.")
                if let error = session.agentsError {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(ClaudeTypography().sans(13))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
    }

    // MARK: Drawers

    private var selectedWorkspace: WorkspaceDescriptor? {
        guard let workspaceId = conversation?.agent?.workspaceId else { return nil }
        return session.workspaceDirectory.workspace(id: workspaceId)
    }

    private func settleDrawer(open: Bool) {
        settle(drawer: open, panel: false)
    }

    private func settlePanel(open: Bool) {
        settle(drawer: false, panel: open)
    }

    private func closeDrawers() {
        settle(drawer: false, panel: false)
    }

    /// Both progresses settle inside one `withAnimation`: opening one drawer closes the other in
    /// the same frame with the same curve, so there is no double animation and no desync (§1.4).
    private func settle(drawer: Bool, panel: Bool) {
        let changed = drawer != isDrawerOpen || panel != isPanelOpen
        isDrawerOpen = drawer
        isPanelOpen = panel
        if !panel { panelTerminalId = nil }
        let animation = EdgeDrawer.settleAnimation(reduceMotion: reduceMotion)
        withAnimation(animation) {
            drawerProgress = drawer ? 1 : 0
            panelProgress = panel ? 1 : 0
        }
        if changed { Haptics.selection() }
    }

    // MARK: Mention in chat

    /// Appends `@relative/path ` to the open conversation's draft (space-separated), closes the
    /// panel and focuses the composer. Light haptic.
    private func mentionInChat(_ relPath: String) {
        guard let store = conversation else {
            settlePanel(open: false)
            return
        }
        let mention = "@\(relPath) "
        if store.draft.isEmpty {
            store.draft = mention
        } else if store.draft.hasSuffix(" ") || store.draft.hasSuffix("\n") {
            store.draft += mention
        } else {
            store.draft += " " + mention
        }
        settlePanel(open: false)
        composerFocusRequested = true
        Haptics.selection()
    }

    // MARK: Selection

    /// Routes a notification tap through the same selection path the sidebar uses. Agent targets
    /// ignore their workspace hint (the agent can move); terminal targets pick the newest agent
    /// in the terminal's workspace and open the workspace panel.
    private func handleNotificationTarget() {
        guard let target = notificationTarget else { return }
        notificationTarget = nil
        settleDrawer(open: false)
        switch target.kind {
        case .agent:
            guard let agentId = target.agentId else { return }
            select(agentId)
        case .terminal:
            settlePanel(open: false)
            let workspaceId =
                target.workspaceId
                ?? target.terminalId.flatMap { session.terminals.workspaceId(forTerminal: $0) }
            guard let workspaceId,
                let agent = session.agents.first(where: { $0.workspaceId == workspaceId })
            else { return }
            panelTerminalId = target.terminalId
            select(agent.id)
            settlePanel(open: true)
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
            settleDrawer(open: false)
            select(agentId)
        case .workspace(_, let workspaceId, let open):
            settleDrawer(open: false)
            if case .agent(let agentId) = open {
                select(agentId)
                return
            }
            guard let agent = session.agents.first(where: { $0.workspaceId == workspaceId }) else {
                // No agent to show yet: the workspace still exists in the sidebar.
                settleDrawer(open: true)
                return
            }
            select(agent.id, closeDrawer: false)
            if case .terminal(let terminalId) = open {
                panelTerminalId = terminalId
                settlePanel(open: true)
            }
        case .host:
            settleDrawer(open: false)
            if selectedAgentId == nil, let first = session.agents.first { select(first.id) }
        case .openProject:
            settleDrawer(open: true)
            addProjectRequested = true
        case .offer, .unsupported:
            // Offers go through RootView's pairing sheet; unsupported routes get a message there.
            break
        }
    }

    private func select(_ agentId: String, closeDrawer: Bool = true) {
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
        if closeDrawer && isDrawerOpen { self.settleDrawer(open: false) }
    }

    /// One route for every "new session" entry point the sidebar owns (U1). U2 replaces the
    /// body with the draft session; until then it opens the existing New agent sheet for the
    /// requested workspace, the current conversation's workspace, or the most recently used one.
    private func openNewSession(workspaceId: String?) {
        if let workspaceId, let workspace = session.workspaceDirectory.workspace(id: workspaceId) {
            openNewAgent(workspace: workspace)
            return
        }
        if let workspace = mostRecentWorkspace {
            openNewAgent(workspace: workspace)
            return
        }
        // No workspace at all: U2's draft shows the hero with an Add project action. Until then,
        // take the user there instead of leaving the pill dead.
        settleDrawer(open: true)
        addProjectRequested = true
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

    private func openNewAgent(prompt: String) {
        guard let agent = conversation?.agent else { return }
        newAgentRequest = NewAgentRequest(
            id: UUID().uuidString,
            workspaceId: agent.workspaceId,
            cwd: agent.cwd,
            prompt: prompt
        )
    }

    private func openNewAgent(workspace: WorkspaceDescriptor) {
        newAgentRequest = NewAgentRequest(
            id: UUID().uuidString,
            workspaceId: workspace.id,
            cwd: workspace.cwd,
            prompt: ""
        )
    }
}

/// One presentation of the new-agent sheet, carrying the composer's first prompt.
private struct NewAgentRequest: Identifiable {
    var id: String
    var workspaceId: String?
    var cwd: String
    var prompt: String

    var trimmedPrompt: String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
