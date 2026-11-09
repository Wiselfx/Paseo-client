#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The action a "Mention in chat" button triggers. Internal, so the panel's pages can reach it
/// without widening their fixed constructors. Nil disables the action.
struct MentionInChatKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

/// The live-file watch (T11) for the workspace the panel shows. Published by the panel;
/// consumed by the Files page and its viewer.
struct WorkspaceGitExtrasKey: EnvironmentKey {
    static let defaultValue: WorkspaceGitExtras? = nil
}

extension EnvironmentValues {
    var mentionInChat: ((String) -> Void)? {
        get { self[MentionInChatKey.self] }
        set { self[MentionInChatKey.self] = newValue }
    }
    var workspaceGitExtras: WorkspaceGitExtras? {
        get { self[WorkspaceGitExtrasKey.self] }
        set { self[WorkspaceGitExtrasKey.self] = newValue }
    }
}

/// The workspace panel: "inside this workspace" — its agents, files, changes and terminals. Slides
/// in from the right edge over the chat, mirroring the left sidebar drawer.
///
/// Agents are listed here, not in the sidebar: tap switches the chat to that agent (and closes
/// the panel). Files/Changes/Terminal construct the fixed stub-page contracts.
struct WorkspacePanel: View {
    let session: HostSession
    let workspace: WorkspaceDescriptor?
    /// The agent the chat is showing; marks the row and is not re-selected on tap.
    let currentAgentId: String?
    var onSelectAgent: (String) -> Void
    var onNewAgent: (WorkspaceDescriptor) -> Void
    /// Inserts `@relative/path ` into the open conversation's composer (see `PaseoShellView`).
    var onMentionInChat: ((String) -> Void)?
    /// A terminal to select when the panel reaches the Terminal page (notification tap).
    var initialTerminalId: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage private var pageRaw: String
    @State private var checkout: CheckoutStore?
    @State private var gitExtras: WorkspaceGitExtras?
    @State private var renamingAgent: AgentSnapshot?
    @State private var agentPendingArchive: AgentSnapshot?
    @State private var renameText = ""
    @State private var showSetupSheet = false
    @State private var showImportSheet = false
    @State private var observedSetupWorkspaceId: String?

    private let typography = ClaudeTypography()

    init(
        session: HostSession, workspace: WorkspaceDescriptor?, currentAgentId: String?,
        onSelectAgent: @escaping (String) -> Void,
        onNewAgent: @escaping (WorkspaceDescriptor) -> Void,
        onMentionInChat: ((String) -> Void)? = nil,
        initialTerminalId: String? = nil
    ) {
        self.session = session
        self.workspace = workspace
        self.currentAgentId = currentAgentId
        self.onSelectAgent = onSelectAgent
        self.onNewAgent = onNewAgent
        self.onMentionInChat = onMentionInChat
        self.initialTerminalId = initialTerminalId
        // The last page is remembered per workspace; a notification tap lands on Terminal.
        let initial: Page = initialTerminalId != nil ? .terminal : .agents
        let id = workspace?.id ?? "none"
        _pageRaw = AppStorage(wrappedValue: initial.rawValue, "paseo.panel.page.\(id)")
    }

    enum Page: String, CaseIterable {
        case agents
        case files
        case changes
        case terminal

        var title: String {
            switch self {
            case .agents: "Agents"
            case .files: "Files"
            case .changes: "Changes"
            case .terminal: "Terminal"
            }
        }
    }

    private var currentPage: Page {
        Page(rawValue: pageRaw) ?? .agents
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            setupQuietLine
            segmented
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            ClaudeDivider()
            content
        }
        .background(ClaudePalette.background)
        .environment(\.mentionInChat, onMentionInChat)
        .environment(\.workspaceGitExtras, gitExtras)
        .onChange(of: initialTerminalId) { _, terminalId in
            if terminalId != nil { pageRaw = Page.terminal.rawValue }
        }
        .task(id: workspace?.id) {
            if let previous = observedSetupWorkspaceId, previous != workspace?.id {
                observedSetupWorkspaceId = nil
                await session.setupObservation.stopObserving(previous)
            }
            guard let workspace else {
                checkout = nil
                gitExtras = nil
                return
            }
            let store = await MainActor.run { session.checkout(for: workspace) }
            let extras = await MainActor.run { session.gitExtras.workspace(for: store) }
            checkout = store
            gitExtras = extras
            observedSetupWorkspaceId = workspace.id
            await session.setupObservation.observe(workspace.id)
        }
        .sheet(isPresented: $showSetupSheet) {
            if let workspace {
                WorkspaceSetupSheet(session: session, workspace: workspace)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            if let workspace {
                ImportSessionSheet(session: session, cwd: workspace.cwd, workspaceId: workspace.id) { agentId in
                    showImportSheet = false
                    onSelectAgent(agentId)
                }
            }
        }
        .alert(
            "Rename agent",
            isPresented: Binding(
                get: { renamingAgent != nil },
                set: { if !$0 { renamingAgent = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingAgent = nil }
            Button("Rename") {
                let target = renamingAgent
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                renamingAgent = nil
                guard let target, !title.isEmpty else { return }
                Task {
                    await session.conversation(for: target.id).rename(to: title)
                    await session.refreshAgents()
                }
            }
        } message: {
            Text("Choose a short name for this agent.")
        }
        .confirmationDialog(
            "Archive agent?",
            isPresented: Binding(
                get: { agentPendingArchive != nil },
                set: { if !$0 { agentPendingArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let agent = agentPendingArchive else { return }
                agentPendingArchive = nil
                Task {
                    await session.conversation(for: agent.id).archive()
                    await session.refreshAgents()
                }
            }
            Button("Cancel", role: .cancel) { agentPendingArchive = nil }
        } message: {
            Text(archiveMessage(for: agentPendingArchive))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(workspaceTitle)
                .font(typography.serif(20, relativeTo: .title3))
                .foregroundStyle(ClaudePalette.ink)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let branch = workspace?.branch {
                    Text(branch)
                        .font(typography.mono(12, relativeTo: .footnote))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
                if let stat = diffStatText {
                    Text("·")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.captionInk)
                    Text(stat)
                        .font(typography.mono(12, relativeTo: .footnote))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// Serif 20 headline: the workspace title, or the branch when there is no title.
    private var workspaceTitle: String {
        guard let workspace else { return "Workspace" }
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    private var diffStatText: String? {
        guard let stat = workspace?.diffStat else { return nil }
        return "+\(stat.additions) −\(stat.deletions)"
    }

    // MARK: Setup quiet line

    /// A quiet status line above the page switcher, shown only while setup is running, failed or
    /// blocked. Tap opens the setup sheet. Hidden entirely otherwise.
    @ViewBuilder private var setupQuietLine: some View {
        if let workspace, let snapshot = session.setupObservation.snapshot(for: workspace.id),
            snapshot.status == .running || snapshot.status == .failed || snapshot.status == .blocked
        {
            Button {
                showSetupSheet = true
            } label: {
                HStack(spacing: 8) {
                    setupGlyph(snapshot.status)
                    Text(setupLineText(snapshot))
                        .font(typography.sans(13, weight: .medium))
                        .foregroundStyle(setupLineInk(snapshot.status))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ClaudePalette.quoteWash)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(setupLineText(snapshot)). Opens setup details.")
        }
    }

    private func setupLineText(_ snapshot: WorkspaceSetupSnapshot) -> String {
        switch snapshot.status {
        case .running: return "Setting up…"
        case .failed: return "Setup failed"
        case .blocked:
            if let blocked = snapshot.blockedSource {
                return "Blocked on change request #\(blocked.number)"
            }
            return "Setup blocked"
        default: return "Setup"
        }
    }

    private func setupLineInk(_ status: WorkspaceSetupStatus) -> Color {
        switch status {
        case .failed: ClaudePalette.failureInk
        case .blocked: ClaudePalette.warning
        default: ClaudePalette.secondaryInk
        }
    }

    @ViewBuilder private func setupGlyph(_ status: WorkspaceSetupStatus) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.mini).tint(ClaudePalette.secondaryInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.failureInk)
        case .blocked:
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClaudePalette.warning)
        default:
            EmptyView()
        }
    }

    // MARK: Page switcher

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Page.allCases, id: \.self) { page in
                Button {
                    select(page)
                } label: {
                    Text(page.title)
                        .font(
                            typography.sans(14, weight: page == currentPage ? .medium : .regular))
                        .foregroundStyle(
                            page == currentPage ? ClaudePalette.background : ClaudePalette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            page == currentPage ? ClaudePalette.ink : Color.clear, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == currentPage ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ClaudePalette.chip, in: .capsule)
    }

    private func select(_ page: Page) {
        guard page != currentPage else { return }
        Haptics.selection()
        if reduceMotion {
            pageRaw = page.rawValue
        } else {
            withAnimation(.easeOut(duration: 0.18)) { pageRaw = page.rawValue }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let workspace {
            switch currentPage {
            case .agents:
                agentsPage(workspace: workspace)
            case .files:
                filesPage
            case .changes:
                changesPage
            case .terminal:
                WorkspaceTerminalsView(
                    session: session, workspace: workspace, initialTerminalId: initialTerminalId)
            }
        } else {
            unavailable
        }
    }

    @ViewBuilder private var filesPage: some View {
        if let checkout {
            WorkspaceFilesView(checkout: checkout)
        } else {
            loadingPage
        }
    }

    @ViewBuilder private var changesPage: some View {
        if let checkout {
            WorkspaceChangesView(
                session: session, checkout: checkout,
                agentId: currentAgentId, workspaceId: workspace?.id)
        } else {
            loadingPage
        }
    }

    private var loadingPage: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading \(currentPage.title.lowercased())")
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No workspace selected")
                .font(typography.sans(16, weight: .medium))
                .foregroundStyle(ClaudePalette.ink)
            Text("Open a workspace from the sidebar to fill this panel.")
                .font(typography.sans(13))
                .foregroundStyle(ClaudePalette.secondaryInk)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Agents page

    private func agentsPage(workspace: WorkspaceDescriptor) -> some View {
        let agents = session.agents.filter { $0.workspaceId == workspace.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                newAgentRow(workspace: workspace)
                if session.agentControl.isSupported {
                    importSessionRow
                }
                if agents.isEmpty {
                    Text("No agents in this workspace yet.")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(agents) { agent in
                        agentRow(agent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func newAgentRow(workspace: WorkspaceDescriptor) -> some View {
        Button {
            Haptics.selection()
            onNewAgent(workspace)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 30, height: 30)
                    .background(ClaudePalette.chip, in: .circle)
                Text("New agent")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New agent")
    }

    private var importSessionRow: some View {
        Button {
            Haptics.selection()
            showImportSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 30, height: 30)
                    .background(ClaudePalette.chip, in: .circle)
                Text("Import session")
                    .font(typography.sans(16, weight: .medium))
                    .foregroundStyle(ClaudePalette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import session")
    }

    private func agentRow(_ agent: AgentSnapshot) -> some View {
        let current = agent.id == currentAgentId
        return Button {
            Haptics.selection()
            onSelectAgent(agent.id)
        } label: {
            HStack(spacing: 12) {
                PaseoStatusDot(kind: agentStatusKind(agent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.title ?? "New agent")
                        .font(typography.sans(16, weight: current ? .medium : .regular))
                        .lineLimit(1)
                    Text(agentMeta(agent))
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let stamp = activityDate(agent) {
                    Text(relativeAge(stamp))
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                }
                if current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ClaudePalette.ink)
                        .accessibilityLabel("Current agent")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(.rect)
            .background(current ? ClaudePalette.chip : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(current ? "Current agent" : "")
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = agent.title ?? ""
                renamingAgent = agent
            }
            Button("Copy agent ID", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = agent.id
                Haptics.selection()
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                agentPendingArchive = agent
            }
        }
    }

    private func agentStatusKind(_ agent: AgentSnapshot) -> PaseoStatusDot.Kind {
        switch agent.attention {
        case .permission: return .needsInput
        case .error: return .failed
        case .finished: return .unread
        case .unknown, nil: break
        }
        switch agent.status {
        case .running: return .running
        case .error: return .failed
        case .initializing, .idle, .closed, .unknown: return .idle
        }
    }

    private func agentMeta(_ agent: AgentSnapshot) -> String {
        let provider = session.agentControl.provider(agent.provider)?.label ?? agent.provider
        guard let model = agent.model else { return provider }
        let label =
            session.agentControl.models(forProvider: agent.provider)
                .first(where: { $0.id == model })?.label ?? model
        return "\(provider) · \(label)"
    }

    /// `updatedAt`, falling back to `lastUserMessageAt` — the list is newest-first either way.
    private func activityDate(_ agent: AgentSnapshot) -> Date? {
        for stamp in [agent.updatedAt, agent.lastUserMessageAt] {
            if let stamp, let date = PaseoDate.parse(stamp) { return date }
        }
        return nil
    }

    /// "now", "5m", "3h", "2d", "4mo" — compact ages for the activity column.
    private func relativeAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        return "\(days / 30)mo"
    }

    private func archiveMessage(for agent: AgentSnapshot?) -> String {
        guard let agent else { return "" }
        if agent.status == .running {
            return "This agent is still running. Archiving it will stop the agent."
        }
        return "The agent will be archived."
    }
}
#endif
