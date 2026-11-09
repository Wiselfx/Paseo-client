#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The app after connecting: a drawer of workspaces and their agents, and the selected agent's
/// conversation. The shells ClaudeUI had (sidebar + one surface) on Paseo's live directory.
public struct PaseoShellView: View {
    let session: HostSession
    var onDisconnect: () -> Void

    @State private var selectedAgentId: String?
    @State private var conversation: ConversationStore?
    @State private var sidebarOpen = false
    @State private var newAgentRequest: NewAgentRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let typography = ClaudeTypography()

    public init(session: HostSession, onDisconnect: @escaping () -> Void) {
        self.session = session
        self.onDisconnect = onDisconnect
        ClaudeFontResources.register()
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ClaudePalette.background.ignoresSafeArea()
                main
                    .background(ClaudePalette.background)
                    .clipShape(.rect(cornerRadius: sidebarOpen ? 44 : 0))
                    .overlay {
                        if sidebarOpen {
                            Color.black.opacity(0.45)
                                .ignoresSafeArea()
                                .onTapGesture { toggleSidebar() }
                        }
                    }
                    .offset(x: sidebarOpen ? geometry.size.width * 0.82 : 0)
                    .shadow(color: .black.opacity(sidebarOpen ? 0.25 : 0), radius: 8)
                if sidebarOpen {
                    PaseoSidebar(
                        session: session, selectedAgentId: selectedAgentId,
                        onSelectAgent: { select($0) },
                        onClose: { toggleSidebar() },
                        onDisconnect: onDisconnect
                    )
                    .frame(width: geometry.size.width * 0.82)
                    .transition(.move(edge: .leading))
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
                onOpenSidebar: { toggleSidebar() },
                onSelectAgent: { select($0) },
                onNewAgent: { prompt in openNewAgent(prompt: prompt) }
            )
            .id(conversation.agentId)
        } else {
            emptyMain
        }
    }

    private var emptyMain: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    toggleSidebar()
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
            Spacer()
            Text("Paseo")
                .font(.custom(typography.serifName, size: 30))
                .foregroundStyle(ClaudePalette.adaptive(light: 0.24, dark: 0.76))
            Text("Pick an agent from the sidebar to start.")
                .font(.system(size: 15))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .multilineTextAlignment(.center)
            if let error = session.agentsError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
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
        if closeDrawer && sidebarOpen { toggleSidebar() }
    }

    private func toggleSidebar() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88)) {
            sidebarOpen.toggle()
        }
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
