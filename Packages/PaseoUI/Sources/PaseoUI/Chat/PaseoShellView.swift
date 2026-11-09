#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One-shot signal from the shell into the composer to take keyboard focus. A Binding so the
/// composer can reset it after consuming. Internal so the composer can see it.
struct ComposerFocusKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var composerFocusRequested: Binding<Bool> {
        get { self[ComposerFocusKey.self] }
        set { self[ComposerFocusKey.self] = newValue }
    }
}

/// The app after connecting: a drawer of workspaces and their agents on the left, the selected
/// agent's conversation in the middle, and the workspace panel sliding in from the right edge.
/// Both edges share the `EdgeDrawer` physics; the main surface tracks the finger, settles by
/// position and velocity, and takes the display's corner radius on all four sides.
public struct PaseoShellView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @State private var selectedAgentId: String?
    @State private var conversation: ConversationStore?
    @State private var newAgentRequest: NewAgentRequest?
    @State private var isDrawerOpen = false
    @State private var drawerProgress: CGFloat = 0
    @State private var isPanelOpen = false
    @State private var panelProgress: CGFloat = 0
    @State private var composerFocusRequested = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let drawerFraction: CGFloat = 0.82
    private let panelFraction: CGFloat = 0.88

    public init(session: HostSession, onDisconnect: @escaping () -> Void) {
        self.session = session
        self.onDisconnect = onDisconnect
        ClaudeFontResources.register()
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let drawerWidth = width * drawerFraction
            let panelWidth = width * panelFraction
            let corner = EdgeDrawer.cornerRadius(forScreenWidth: width)
            ZStack(alignment: .leading) {
                ClaudePalette.sidebarBackground.ignoresSafeArea()
                PaseoSidebar(
                    session: session,
                    selectedAgentId: selectedAgentId,
                    onSelectAgent: { select($0) },
                    onNewAgent: { openNewAgent(workspace: $0) },
                    onDisconnect: onDisconnect
                )
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                main
                    .frame(width: width, height: geometry.size.height)
                    .background(ClaudePalette.background.ignoresSafeArea())
                    .environment(\.composerFocusRequested, $composerFocusRequested)
                    .clipShape(
                        .rect(cornerRadius: corner * drawerProgress, style: .continuous)
                    )
                    .overlay {
                        EdgeDrawerDim(progress: drawerProgress) { settleDrawer(open: false) }
                    }
                    .offset(x: drawerWidth * drawerProgress)
                    .shadow(
                        color: .black.opacity(0.25 * Double(drawerProgress)),
                        radius: 8 * drawerProgress)
                    .edgeDrawerDrag(
                        edge: .leading, screenWidth: width, drawerWidth: drawerWidth,
                        isOpen: isDrawerOpen, blocked: isPanelOpen,
                        progress: $drawerProgress, onSettle: { settleDrawer(open: $0) })
                    .edgeDrawerDrag(
                        edge: .trailing, screenWidth: width, drawerWidth: panelWidth,
                        isOpen: isPanelOpen, blocked: isDrawerOpen,
                        progress: $panelProgress, onSettle: { settlePanel(open: $0) })

                EdgeDrawerDim(progress: panelProgress) { settlePanel(open: false) }

                if isPanelOpen || panelProgress > 0 {
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
                        onMentionInChat: mentionInChat
                    )
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(
                        .rect(cornerRadius: corner * panelProgress, style: .continuous)
                    )
                    .shadow(
                        color: .black.opacity(0.25 * Double(panelProgress)),
                        radius: 8 * panelProgress)
                    .offset(x: width - panelWidth * panelProgress)
                    .edgeDrawerDrag(
                        edge: .trailing, screenWidth: width, drawerWidth: panelWidth,
                        isOpen: isPanelOpen, blocked: isDrawerOpen,
                        progress: $panelProgress, onSettle: { settlePanel(open: $0) })
                }
            }
            .clipped()
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
            if selectedAgentId == nil, let first = session.agents.first { select(first.id, closeDrawer: false) }
        }
        .onDisappear {
            session.hostSettings.stopPresence()
        }
        .onChange(of: selectedAgentId) { _, id in
            session.hostSettings.updateFocus(id)
        }
        .onChange(of: scenePhase) { _, phase in
            session.hostSettings.updateVisibility(phase == .active)
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

    // MARK: Main

    @ViewBuilder private var main: some View {
        if let conversation {
            ClaudeChatView(
                session: session,
                store: conversation,
                onOpenSidebar: { settleDrawer(open: true) },
                onOpenPanel: { settlePanel(open: true) },
                onNewAgent: { prompt in openNewAgent(prompt: prompt) }
            )
            .id(conversation.agentId)
        } else {
            emptyMain
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
        let changed = open != isDrawerOpen
        if open { settlePanel(open: false) }
        isDrawerOpen = open
        let animation: Animation = EdgeDrawer.settleAnimation(reduceMotion: reduceMotion)
        withAnimation(animation) {
            drawerProgress = open ? 1 : 0
        }
        if changed { Haptics.selection() }
    }

    private func settlePanel(open: Bool) {
        let changed = open != isPanelOpen
        if open { settleDrawer(open: false) }
        isPanelOpen = open
        let animation: Animation = EdgeDrawer.settleAnimation(reduceMotion: reduceMotion)
        withAnimation(animation) {
            panelProgress = open ? 1 : 0
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
