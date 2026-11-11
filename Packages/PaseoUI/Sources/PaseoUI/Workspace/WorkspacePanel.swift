#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The action a "Mention in chat" button triggers. Internal, so the panel's pages can reach it
/// without widening their fixed constructors. Nil disables the action.
struct MentionInChatKey: EnvironmentKey {
    static var defaultValue: ((String) -> Void)? { nil }
}

/// The live-file watch (T11) for the workspace the panel shows. Published by the panel;
/// consumed by the Files page and its viewer.
struct WorkspaceGitExtrasKey: EnvironmentKey {
    static var defaultValue: WorkspaceGitExtras? { nil }
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
    /// Inserts `@relative/path ` into the open conversation's composer (see `ShellView`).
    var onMentionInChat: ((String) -> Void)?
    /// A terminal to select when the panel reaches the Terminal page (notification tap).
    var initialTerminalId: String? = nil
    /// Closes the panel: the header's back chevron (§1.3).
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toast) private var toast
    @AppStorage private var pageRaw: String
    @State private var checkout: CheckoutStore?
    @State private var gitExtras: WorkspaceGitExtras?
    @State private var renamingAgent: AgentSnapshot?
    @State private var agentPendingArchive: AgentSnapshot?
    @State private var renameText = ""
    @State private var showSetupSheet = false
    @State private var showImportSheet = false
    @State private var observedSetupWorkspaceId: String?
    @Environment(\.shellDrawer) private var shellDrawer
    /// Whether the shell's drawer has the panel on screen. The page content is mounted only
    /// while this is true, so closing the panel stops its work; the tab is remembered separately.
    @Environment(\.isPanelVisible) private var isPanelVisible

    init(
        session: HostSession, workspace: WorkspaceDescriptor?, currentAgentId: String?,
        onSelectAgent: @escaping (String) -> Void,
        onNewAgent: @escaping (WorkspaceDescriptor) -> Void,
        onMentionInChat: ((String) -> Void)? = nil,
        initialTerminalId: String? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.session = session
        self.workspace = workspace
        self.currentAgentId = currentAgentId
        self.onSelectAgent = onSelectAgent
        self.onNewAgent = onNewAgent
        self.onMentionInChat = onMentionInChat
        self.initialTerminalId = initialTerminalId
        self.onClose = onClose
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

        /// UX-SPEC §0.3.
        var symbol: String {
            switch self {
            case .agents: "bubble.left.and.bubble.right"
            case .files: "folder"
            case .changes: "plus.forwardslash.minus"
            case .terminal: "apple.terminal"
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
            dismissableContent
        }
        // One canvas for every panel page and pushed page (E2 §5): the panel fill, the same one
        // the Changes tab draws. The shell card behind it is never what shows through.
        .background { Palette.panel.ignoresSafeArea() }
        .environment(\.mentionInChat, onMentionInChat)
        .environment(\.workspaceGitExtras, gitExtras)
        .onChange(of: initialTerminalId) { _, terminalId in
            if terminalId != nil { pageRaw = Page.terminal.rawValue }
        }
        .task(id: isPanelVisible ? workspace?.id : nil) {
            guard !Task.isCancelled else { return }
            // Closed: drop the setup watch and the page's stores. The checkout and terminal
            // attachments are released by `releaseWorkspaceWork` when the page disappears.
            guard isPanelVisible else {
                await stopSetupObservation()
                guard !Task.isCancelled else { return }
                checkout = nil
                gitExtras = nil
                return
            }
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
            guard isPanelVisible, !Task.isCancelled else {
                await session.closeCheckout(workspace.id)
                return
            }
            let extras = await MainActor.run { session.gitExtras.workspace(for: store) }
            guard isPanelVisible, !Task.isCancelled else {
                await session.closeCheckout(workspace.id)
                return
            }
            checkout = store
            gitExtras = extras
            observedSetupWorkspaceId = workspace.id
            await session.setupObservation.observe(workspace.id)
            // The workspace changed (or the panel closed) while the subscribe was in flight.
            guard !Task.isCancelled else {
                await session.setupObservation.stopObserving(workspace.id)
                return
            }
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
                archive(agent)
            }
            Button("Cancel", role: .cancel) { agentPendingArchive = nil }
        } message: {
            Text(archiveMessage(for: agentPendingArchive))
        }
    }

    // MARK: Header

    /// The panel header (§1.3): a back chevron leading, the workspace name centered, and the
    /// page's secondary actions trailing. A horizontal drag on it dismisses the panel through the
    /// shell's pan.
    private var header: some View {
        ShellHeader(leading: .back({ close() })) {
            Text(workspaceTitle)
                .font(.paseo(.title))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        } trailing: {
            Menu {
                if session.agentControl.isSupported {
                    Button("Import session", systemImage: "square.and.arrow.down") {
                        showImportSheet = true
                    }
                }
                if let workspace {
                    Button("Setup…", systemImage: "wrench.and.screwdriver") {
                        showSetupSheet = true
                    }
                    Button("Copy path", systemImage: "doc.on.doc") {
                        Clipboard.copy(workspace.cwd, toast: toast)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.glyph(.regular, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Workspace actions")
        }
        .padding(.top, Space.xs)
        .contentShape(.rect)
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

    /// The panel closes through the shell's drawer: the back button is one of its dismissal
    /// routes (UX-SPEC §1.3).
    private func close() {
        if let shellDrawer {
            shellDrawer.close()
        } else {
            onClose()
        }
    }

    @ViewBuilder private var dismissableContent: some View {
        if isPanelVisible {
            PanelPage {
                content
            }
            .onDisappear {
                if let workspace {
                    releaseWorkspaceWork(workspace)
                }
            }
        } else {
            EmptyView()
        }
    }

    /// Stops the setup watch. Used when the panel closes and when the workspace changes.
    private func stopSetupObservation() async {
        if let previous = observedSetupWorkspaceId {
            observedSetupWorkspaceId = nil
            await session.setupObservation.stopObserving(previous)
        }
    }

    /// Releases the page's stores when the panel closes or the workspace changes: the checkout
    /// (and its diff subscription) and the workspace's terminal attachments. Both are recreated
    /// lazily on the next open.
    private func releaseWorkspaceWork(_ workspace: WorkspaceDescriptor) {
        checkout = nil
        gitExtras = nil
        session.terminals.close(workspaceId: workspace.id)
        let session = self.session
        let workspaceId = workspace.id
        Task {
            await session.closeCheckout(workspaceId)
            await session.setupObservation.stopObserving(workspaceId)
        }
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
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(setupLineInk(snapshot.status))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.tertiaryInk)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Palette.quoteWash)
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
        case .failed: Palette.failureInk
        case .blocked: Palette.warning
        default: Palette.secondaryInk
        }
    }

    @ViewBuilder private func setupGlyph(_ status: WorkspaceSetupStatus) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.mini).tint(Palette.secondaryInk)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.failureInk)
        case .blocked:
            Image(systemName: "clock.badge.exclamationmark")
                .font(.glyph(.small, weight: .medium))
                .foregroundStyle(Palette.warning)
        default:
            EmptyView()
        }
    }

    // MARK: Page switcher

    private var segmented: some View {
        Picker(
            "Workspace page",
            selection: Binding(
                get: { currentPage },
                set: { select($0) })
        ) {
            ForEach(Page.allCases, id: \.self) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
        }
        .pickerStyle(.segmented)
    }

    private func select(_ page: Page) {
        guard page != currentPage else { return }
        Haptics.selection()
        if reduceMotion {
            pageRaw = page.rawValue
        } else {
            withAnimation(Motion.disclosure.animation) { pageRaw = page.rawValue }
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
        LoadingState()
    }

    private var unavailable: some View {
        EmptyState(
            title: "No workspace selected",
            message: "Open a workspace from the sidebar to fill this panel.")
    }

    // MARK: Agents page

    private func agentsPage(workspace: WorkspaceDescriptor) -> some View {
        let agents = session.agents.filter { $0.workspaceId == workspace.id }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ListRow(
                    title: "New session",
                    systemImage: "plus",
                    action: { onNewAgent(workspace) }
                )
                if agents.isEmpty {
                    EmptyState(
                        systemImage: "bubble.left.and.bubble.right",
                        title: "No agents in this workspace yet.")
                    .padding(.vertical, Space.xxl)
                } else {
                    ForEach(agents) { agent in
                        RowDivider()
                        agentRow(agent)
                    }
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.lg)
        }
        .scrollIndicators(.hidden)
    }

    private func agentRow(_ agent: AgentSnapshot) -> some View {
        let current = agent.id == currentAgentId
        let subtitle: String = {
            let meta = agentMeta(agent)
            guard let stamp = activityDate(agent) else { return meta }
            return "\(meta) · \(PaseoFormat.relative(stamp))"
        }()
        return HStack(spacing: 0) {
            StatusDot(agentStatusState(agent))
                .padding(.leading, Space.lg)
            ListRow(
                title: agent.title ?? "New agent",
                subtitle: subtitle,
                accessory: current ? .checkmark(true) : .none,
                action: { onSelectAgent(agent.id) }
            )
        }
        .contentShape(.rect)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right") {
                onSelectAgent(agent.id)
            }
            Button("Rename…", systemImage: "pencil") {
                renameText = agent.title ?? ""
                renamingAgent = agent
            }
            Button("Copy agent ID", systemImage: "doc.on.doc") {
                Clipboard.copy(agent.id, toast: toast)
                Haptics.light()
            }
            Divider()
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                requestArchive(agent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(current ? "Current agent" : "")
    }

    private func agentStatusState(_ agent: AgentSnapshot) -> StatusDot.State {
        switch agent.attention {
        case .permission: return .attention
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

    /// Confirm only while the agent is running; otherwise archive at once with an Undo toast.
    private func requestArchive(_ agent: AgentSnapshot) {
        if agent.status == .running {
            agentPendingArchive = agent
        } else {
            archive(agent)
        }
    }

    private func archive(_ agent: AgentSnapshot) {
        Task {
            await session.conversation(for: agent.id).archive()
            await session.refreshAgents()
            Haptics.light()
            toast?.show(
                "Agent archived",
                undo: {
                    Task {
                        _ = await session.agentLifecycle.unarchive(agentId: agent.id)
                        await session.refreshAgents()
                    }
                })
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

    private func archiveMessage(for agent: AgentSnapshot?) -> String {
        guard let agent else { return "" }
        if agent.status == .running {
            return "This agent is still running. Archiving it will stop the agent."
        }
        return "The agent will be archived."
    }
}

/// A stable identity for the mounted page, so `.onDisappear` fires when the panel closes or the
/// workspace changes, but not when the selected tab changes.
private struct PanelPage<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View { content() }
}
#endif
