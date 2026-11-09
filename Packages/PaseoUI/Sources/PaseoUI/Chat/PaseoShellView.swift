#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The app after connecting: a drawer of workspaces and their agents, and the selected agent's
/// conversation. The content panel tracks the finger, settles on position and velocity, and takes
/// the display's corner radius on all four sides.
public struct PaseoShellView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @State private var selectedAgentId: String?
    @State private var conversation: ConversationStore?
    @State private var newAgentRequest: NewAgentRequest?
    @State private var isDrawerOpen = false
    @State private var drawerProgress: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let edgeZone: CGFloat = 24
    private let drawerFraction: CGFloat = 0.82

    public init(session: HostSession, onDisconnect: @escaping () -> Void) {
        self.session = session
        self.onDisconnect = onDisconnect
        ClaudeFontResources.register()
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let drawerWidth = width * drawerFraction
            let corner = displayCornerRadius(width: width)
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
                    .clipShape(
                        .rect(cornerRadius: corner * drawerProgress, style: .continuous)
                    )
                    .overlay {
                        if drawerProgress > 0 {
                            Color.black.opacity(0.45 * Double(drawerProgress))
                                .contentShape(.rect)
                                .onTapGesture { closeDrawer() }
                        }
                    }
                    .offset(x: drawerWidth * drawerProgress)
                    .shadow(
                        color: .black.opacity(0.25 * Double(drawerProgress)),
                        radius: 8 * drawerProgress)
                    .simultaneousGesture(drawerDrag(drawerWidth: drawerWidth))
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
            if selectedAgentId == nil, let first = session.agents.first { select(first.id, closeDrawer: false) }
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
                onSelectAgent: { select($0) },
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
                ClaudeHomeHero(hint: "Pick an agent from the sidebar to start.")
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

    // MARK: Drawer

    private func drawerDrag(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    guard isDrawerOpen || value.startLocation.x <= edgeZone else { return }
                    dragOrigin = drawerProgress
                    Haptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let next = origin + value.translation.width / max(1, drawerWidth)
                drawerProgress = min(1, max(0, next))
            }
            .onEnded { value in
                guard let origin = dragOrigin else { return }
                dragOrigin = nil
                let projected = origin + value.predictedEndTranslation.width / max(1, drawerWidth)
                settleDrawer(open: projected >= 0.5)
            }
    }

    private func settleDrawer(open: Bool) {
        let changed = open != isDrawerOpen
        isDrawerOpen = open
        let animation: Animation =
            reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.36, dampingFraction: 0.88)
        withAnimation(animation) {
            drawerProgress = open ? 1 : 0
        }
        if changed { Haptics.selection() }
    }

    private func closeDrawer() {
        settleDrawer(open: false)
    }

    private func displayCornerRadius(width: CGFloat) -> CGFloat {
        min(55, max(44, width * 0.12))
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
        if closeDrawer && isDrawerOpen { self.closeDrawer() }
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
