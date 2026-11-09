#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One agent's conversation, rendered from `ConversationStore.turns` in ClaudeUI's clothes.
///
/// Layout follows `docs/research/06-dsh-ux-spec.md` §1 (turn structure, the counted work group,
/// the 36 pt process rows) and §2 (the live status line), on top of the M2 seam in
/// `docs/research/07-claudeui-adoption-map.md` §5.4. No networking here: everything is store state
/// and store calls.
public struct ClaudeChatView: View {
    let session: HostSession
    @Bindable var store: ConversationStore

    /// The drawer affordance in the shell. Nil keeps the leading edge empty.
    var onOpenSidebar: (() -> Void)?
    /// The panel affordance in the shell. Nil keeps the trailing edge a placeholder.
    var onOpenPanel: (() -> Void)?
    /// Back affordance for a plain navigation stack.
    var onBack: (() -> Void)?
    /// Called with the composer's text so a new agent can start with it.
    var onNewAgent: ((String) -> Void)?

    private let typography = ClaudeTypography()

    @State private var sheet: ClaudeChatSheet?
    @State private var toast: String?
    @FocusState private var focused: Bool
    /// One-shot "focus the composer" signal from the shell (e.g. after "Mention in chat").
    @Environment(\.composerFocusRequested) private var composerFocusRequested
    // Find in conversation (M7 §2). The transcript owns the scroll; `store.search` owns the matches.
    @State private var findOpen = false
    @State private var findQuery = ""
    @State private var findIndex = 0
    @State private var findFlash: Int?
    @State private var findAnchor: String?
    @State private var findSearchTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?
    /// The last turn row that appeared; the find restore anchors to it.
    @State private var lastTrackedTurn: String?
    @FocusState private var findFocused: Bool
    // Chat-follow (M7b §1).
    @State private var isFollowing = true
    @State private var composerHeight: CGFloat = 0
    /// One quiet line per permission answer made this session; the store drops resolved
    /// requests without remembering the answer, so the client keeps the record.
    @State private var permissionResolvedLines: [AnsweredPermission] = []
    /// A file tapped from a Read/Edit/Write row; presented as the existing Files viewer in a sheet.
    @State private var openFilePath: String?
    // Header title menu (M7 §1).
    @State private var renamingAgent = false
    @State private var renameText = ""
    @State private var archiveAgentConfirm = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// M5a: the DSH crab above the composer, driven by the conversation's turns.
    @AppStorage(PaseoSettingsKeys.mascot) private var mascotEnabled = true
    @State private var mascot = MascotStateMachine()
    /// Failed tool calls we've already told the mascot about, by `callId`.
    @State private var signalledToolFailureIds: Set<String> = []
    /// Whether the machine has been told a compaction is open (edge detection for rows).
    @State private var compactionOpen = false
    /// Baseline for the rising edge so an existing badge doesn't fire on appear.
    @State private var attentionActive = false
    /// M8a: slash commands for this agent (`/` at the start of the draft opens the menu).
    @State private var slashCommands: [AgentSlashCommand] = []
    @State private var slashState: SlashCommandState = .idle
    @State private var slashError: String?
    /// M8b: the queue for this agent, kept app-side so it survives switching agents.
    @State private var composerQueue = ComposerQueueStore.shared
    /// M8b: the full-height editor for long drafts (expand control in the card's top-right).
    @State private var showFullScreenComposer = false
    /// M8b: debounce for saved-draft writes (~500 ms).
    @State private var draftSaveTask: Task<Void, Never>?

    private enum SlashCommandState {
        case idle, loading, ready
    }

    public init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onOpenPanel: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        self.onOpenSidebar = onOpenSidebar
        self.onOpenPanel = onOpenPanel
        self.onBack = onBack
        self.onNewAgent = onNewAgent
        ClaudeFontResources.register()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if findOpen {
                findBar
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            if let banner = connectionBanner {
                banner.padding(.horizontal, 16).padding(.bottom, 6)
            }
            content
            composer
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    composerHeight = height
                }
        }
        .background(ClaudePalette.background.ignoresSafeArea())
        .foregroundStyle(ClaudePalette.ink)
        .tint(ClaudePalette.ink)
        .overlay(alignment: .bottom) { backToEnd }
        .sheet(item: $sheet) { _ in
            ClaudeAgentControlsSheet(session: session, store: store)
        }
        .sheet(isPresented: Binding(
            get: { openFilePath != nil },
            set: { if !$0 { openFilePath = nil } })) {
                if let agent = store.agent,
                    let workspaceId = agent.workspaceId,
                    let workspace = session.workspaceDirectory.workspace(id: workspaceId)
                {
                    NavigationStack {
                        WorkspaceFileViewer(
                            checkout: session.checkout(for: workspace),
                            relPath: openFilePath ?? "",
                            onBack: { openFilePath = nil },
                            backLabel: "Files")
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                } else {
                    // The agent's workspace isn't loaded (rare: directory fetch pending).
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                        Text("Workspace not available")
                            .font(typography.sans(15, weight: .medium))
                            .foregroundStyle(ClaudePalette.ink)
                        Button("Close") { openFilePath = nil }
                            .font(typography.sans(15, weight: .medium))
                            .foregroundStyle(ClaudePalette.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 36)
                            .background(ClaudePalette.chip, in: .capsule)
                    }
                    .presentationDetents([.height(240)])
                }
            }
        .animation(.easeInOut(duration: 0.15), value: isFollowing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: findOpen)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(typography.sans(13))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect()
                    .padding(.top, 58)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: store.lastNotice?.message) { _, message in
            guard let message else { return }
            showToast(message)
            store.clearNotice()
        }
        .onChange(of: store.isRunning) { wasRunning, isRunning in
            if wasRunning && !isRunning { Haptics.settle() }
        }
        .onAppear { seedMascotBaselines() }
        .onAppear { seedSavedDraft() }
        .task { await loadSlashCommands() }
        .onChange(of: store.activeTurnId) { oldId, newId in
            if newId == nil, oldId != nil { flushQueuedMessage() }
        }
        .onChange(of: store.draft) { _, newValue in
            scheduleDraftSave(newValue)
        }
        .onChange(of: store.activeTurnId) { _, newId in
            let now = Date()
            if newId != nil {
                feedMascot(.turnStarted(at: now))
            } else {
                // The turn ended; how it landed is in the turns it left behind.
                switch store.turns.last?.phase {
                case .failed: feedMascot(.turnFailed(at: now))
                default: feedMascot(.turnCompleted(at: now))
                }
            }
        }
        .onChange(of: mascotActivitySignature) { _, signature in
            // Newest-row heuristic: reasoning streams think, a running tool call works.
            switch signature.split(separator: "|").last {
            case "reasoning": feedMascot(.activityChanged(.reasoning, at: Date()))
            case "toolCall": feedMascot(.activityChanged(.working, at: Date()))
            default: break
            }
        }
        .onChange(of: failedToolCallIds) { _, ids in
            let unseen = ids.filter { !signalledToolFailureIds.contains($0) }
            guard !unseen.isEmpty else { return }
            for _ in unseen { feedMascot(.toolFailed(at: Date())) }
            signalledToolFailureIds.formUnion(unseen)
        }
        .onChange(of: runningSubagents) { _, count in
            feedMascot(.subagentsChanged(count: count, at: Date()))
        }
        .onChange(of: lastCompactionStatus) { _, status in
            let now = Date()
            if status == "loading" {
                if !compactionOpen {
                    compactionOpen = true
                    feedMascot(.compactionStarted(at: now))
                }
            } else if compactionOpen {
                compactionOpen = false
                feedMascot(.compactionEnded(failed: status == "failed", at: now))
            }
        }
        .onChange(of: busySessions) { _, count in
            feedMascot(.busySessionsChanged(count: count, at: Date()))
        }
        .onChange(of: pendingInteractions) { _, count in
            feedMascot(.pendingInteractionsChanged(count: count, at: Date()))
        }
        .onChange(of: attentionCount) { _, count in
            let active = count > 0
            if active, !attentionActive { feedMascot(.attention(at: Date())) }
            attentionActive = active
        }
        .onChange(of: store.draft) { _, _ in
            feedMascot(.userActivity(at: Date()))
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { feedMascot(.userActivity(at: Date())) }
        }
        .task {
            // The sleep timer advances without events: 60 quiet seconds dozes off.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                mascot.tick(now: Date())
            }
        }
    }

    // MARK: Find in conversation

    /// The seqEnd of the match currently on screen; nil when the results are empty.
    private var findSeq: Int? {
        let locations = store.search.locations
        guard findIndex < locations.count else { return nil }
        return locations[findIndex].seq
    }

    private var findBar: some View {
        ClaudeFindBar(
            typography: typography, query: $findQuery,
            isSearching: store.search.isSearching,
            resultCount: store.search.locations.count, currentIndex: findIndex,
            error: store.search.error,
            onStep: stepFind, onCancel: closeFind, focused: $findFocused)
    }

    private func openFind() {
        Haptics.selection()
        guard !findOpen else { return }
        findAnchor = lastTrackedTurn // restore at turn granularity; bottom stays bottom
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { findOpen = true }
        findFocused = true
    }

    private func closeFind() {
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { findOpen = false }
        findQuery = ""
        findSearchTask?.cancel()
        findSearchTask = nil
        store.search.clear()
        findFocused = false
    }

    private func stepFind(_ delta: Int) {
        let locations = store.search.locations
        guard !locations.isEmpty else { return }
        let next = min(max(0, findIndex + delta), locations.count - 1)
        guard next != findIndex else { return }
        findIndex = next
        scrollToFindMatch(animated: true)
    }

    private func scrollToFindMatch(animated: Bool) {
        guard let seq = findSeq else { return }
        flash(seq)
        guard let scrollProxy else { return }
        if animated {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                scrollProxy.scrollTo("row:\(seq)", anchor: .center)
            }
        } else {
            scrollProxy.scrollTo("row:\(seq)", anchor: .center)
        }
    }

    private func flash(_ seq: Int) {
        findFlash = seq
        let captured = seq
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if findFlash == captured { findFlash = nil }
        }
    }

    private func restoreScroll(proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            if let findAnchor, store.turns.contains(where: { $0.id == findAnchor }) {
                // The anchor belongs to this conversation (closing find on an agent switch may
                // leave it pointing at garbage from the previous one).
                proxy.scrollTo(findAnchor, anchor: .top)
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func scheduleSearch(_ query: String) {
        findSearchTask?.cancel()
        findSearchTask = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            store.search.clear()
            return
        }
        findSearchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await store.search.search(trimmed)
            findIndex = 0
            scrollToFindMatch(animated: true)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    UnequalMenu().stroke(
                        ClaudePalette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                    .frame(width: 18, height: 17)
                    .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open sidebar")
            } else if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Menu {
                Button("Search in conversation", systemImage: "magnifyingglass") {
                    openFind()
                }
                Button("Rename…", systemImage: "pencil") {
                    beginRename()
                }
                Button("Copy agent ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = store.agentId
                    Haptics.selection()
                    showToast("Agent ID copied")
                }
                Divider()
                Button("Archive agent", systemImage: "archivebox", role: .destructive) {
                    archiveAgentConfirm = true
                }
            } label: {
                VStack(alignment: .center, spacing: 1) {
                    Text(store.agent?.title ?? "Agent")
                        .font(typography.serif(20, relativeTo: .headline))
                        .lineLimit(1)
                    if let workspaceLine {
                        Text(workspaceLine)
                            .font(typography.sans(12))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(.rect)
            }
            .accessibilityLabel("Agent menu")
            if let onOpenPanel {
                Button(action: onOpenPanel) {
                    Image(systemName: "sidebar.right").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(in: .circle)
                .accessibilityLabel("Open workspace panel")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
        .alert("Rename agent", isPresented: $renamingAgent) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { await store.rename(to: trimmed) }
            }
        } message: {
            Text("The name shown in the sidebar and the header.")
        }
        .confirmationDialog(
            "Archive agent?",
            isPresented: $archiveAgentConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task { await store.archive() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                store.isRunning
                    ? "This agent is still running. Archiving it will stop the agent."
                    : "The agent will disappear from your list.")
        }
    }

    /// `workspace · branch`, small and secondary under the agent title.
    private var workspaceLine: String? {
        guard
            let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return nil }
        let title = workspaceTitle(workspace)
        if let branch = workspace.branch, branch != title {
            return "\(title) · \(branch)"
        }
        return title
    }

    /// Workspace title, or the branch when there is no title.
    private func workspaceTitle(_ workspace: WorkspaceDescriptor) -> String {
        if let title = workspace.title,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return title
        }
        return workspace.branch ?? workspace.name
    }

    private var modelLabel: String? {
        guard let agent = store.agent else { return nil }
        if let id = agent.model,
            let match = session.agentControl.models(forProvider: agent.provider).first(where: { $0.id == id })
        {
            return match.label
        }
        return session.agentControl.defaultModel(forProvider: agent.provider)?.label ?? agent.model
    }

    private func newAgent(draft: String) {
        focused = false
        onNewAgent?(draft)
    }

    private func openFileViewer(at path: String) {
        Haptics.selection()
        openFilePath = path
    }

    private func beginRename() {
        Haptics.selection()
        renameText = store.agent?.title ?? ""
        renamingAgent = true
    }

    // MARK: Connection

    private var connectionBanner: AnyView? {
        switch session.connection {
        case .reconnecting(let attempt, _):
            return AnyView(
                bannerRow("Reconnecting to host", detail: "Attempt \(attempt)"))
        case .failed:
            return AnyView(bannerRow("Disconnected", detail: nil))
        case .idle, .connecting, .connected:
            return nil
        }
    }

    private func bannerRow(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 13))
            Text(title).font(typography.sans(13, weight: .medium))
            if let detail {
                Text(detail).font(typography.sans(13)).foregroundStyle(ClaudePalette.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ClaudePalette.secondaryInk)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(ClaudePalette.adaptive(light: 0.95, dark: 0.18), in: .rect(cornerRadius: 10))
    }

    // MARK: Transcript

    @ViewBuilder private var content: some View {
        if store.turns.isEmpty, store.pendingPermissions.isEmpty {
            switch store.phase {
            case .loading:
                Spacer()
                ProgressView()
                Spacer()
            case .failed(let message):
                emptyState(title: "Couldn't load agent history", detail: message)
            case .ready:
                ClaudeHomeHero(hint: nil)
            }
        } else {
            transcript
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(typography.serif(25, relativeTo: .title))
                .foregroundStyle(ClaudePalette.ink)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(typography.sans(14))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 27) {
                        if store.timeline.hasOlder { olderHistoryRow }
                        ForEach(store.turns) { turn in
                            ClaudeTurnView(
                                turn: turn, typography: typography,
                                onMarkdown: handleMarkdown, localImageLoader: localImageLoader,
                                highlightedSeq: findFlash,
                                findTarget: findSeq,
                                onOpenFile: { path in openFileViewer(at: path) }
                            )
                            .id(turn.id)
                            .onAppear { lastTrackedTurn = turn.id }
                        }
                        if !store.pendingPermissions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(store.pendingPermissions) { request in
                                    ClaudePermissionCard(
                                        request: request, store: store,
                                        onAnswered: { answered in
                                            permissionResolvedLines.append(answered)
                                        })
                                }
                            }
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.22),
                                value: store.pendingPermissions.count)
                        }
                        if !permissionResolvedLines.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(permissionResolvedLines) { item in
                                    resolvedPermissionLine(item.line)
                                }
                            }
                            .transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .bottom) { transcriptFade }
                // Follows the tail as it streams; loading older pages at the top does not jump.
                .onChange(of: store.turns.last) { _, _ in
                    guard !findOpen, isFollowing else { return }
                    scrollToBottom(proxy)
                }
                .onChange(of: store.pendingPermissions) { _, _ in
                    guard !findOpen, isFollowing else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrollToBottom(proxy) }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        isFollowing = true
                        scrollToBottom(proxy)
                    }
                }
                // Switching the open agent lands the transcript at the bottom, without animation —
                // unless a find session is active; a session belongs to its agent, so it closes.
                .onChange(of: store.agentId) { _, _ in
                    if findOpen {
                        closeFind()
                        return
                    }
                    isFollowing = true
                    scrollToBottom(proxy, animated: false)
                }
                .onAppear {
                    scrollProxy = proxy
                    isFollowing = true
                    if !findOpen { scrollToBottom(proxy, animated: false) }
                }
                .onChange(of: findOpen) { _, isOpen in
                    if !isOpen { restoreScroll(proxy: proxy) }
                }
                .onChange(of: findQuery) { _, query in
                    findIndex = 0
                    scheduleSearch(query)
                }
                .onScrollGeometryChange(for: ScrollFollowMetrics.self) { geometry in
                    ScrollFollowMetrics(
                        distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y
                            - geometry.bounds.height,
                        viewportHeight: geometry.bounds.height)
                } action: { _, metrics in
                    if metrics.distanceFromBottom <= 16 {
                        if !isFollowing { isFollowing = true }
                    } else if metrics.distanceFromBottom > metrics.viewportHeight / 3 {
                        if isFollowing { isFollowing = false }
                    }
                }
                .environment(\.claudeProcessCap, min(400, geometry.size.height * 0.5))
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private struct ScrollFollowMetrics: Equatable {
        var distanceFromBottom: CGFloat
        var viewportHeight: CGFloat
    }

    /// The 40 pt fade band: the transcript melts into the canvas just above the composer.
    private var transcriptFade: some View {
        LinearGradient(
            stops: [
                .init(color: ClaudePalette.background.opacity(0), location: 0),
                .init(color: ClaudePalette.background, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 40)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "Back to the end": visible only while the reader has scrolled up more than a screen-third.
    @ViewBuilder private var backToEnd: some View {
        if !findOpen && !isFollowing {
            Button {
                Haptics.selection()
                isFollowing = true
                if let scrollProxy {
                    if reduceMotion {
                        scrollProxy.scrollTo("bottom", anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.3)) { scrollProxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ClaudePalette.ink)
                    .frame(width: 34, height: 34)
                    .background(ClaudePalette.panel, in: .circle)
                    .overlay {
                        Circle().strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, composerHeight + 12)
            .transition(.opacity)
            .accessibilityIdentifier("transcript.backToEnd")
            .accessibilityLabel("Back to the end")
        }
    }

    private func resolvedPermissionLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
            Text(text)
                .font(typography.sans(12))
        }
        .foregroundStyle(ClaudePalette.tertiaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(text)
    }

    private var olderHistoryRow: some View {
        Group {
            if store.isLoadingOlder {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else {
                Button {
                    Task { await store.loadOlder() }
                } label: {
                    Text("Load earlier")
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 30)
        // Reaching the top fetches one older page; the row stays put so it does not loop.
        .onAppear { Task { await store.loadOlder() } }
    }

    // MARK: Mascot (M5a)

    private func feedMascot(_ event: MascotEvent) {
        mascot.handle(event)
    }

    /// Runs once when the view appears: baselines the one-shot histories so opening the
    /// conversation doesn't re-fire them, then hands the machine the current levels.
    private func seedMascotBaselines() {
        let now = Date()
        signalledToolFailureIds = Set(failedToolCallIds)
        attentionActive = attentionCount > 0
        compactionOpen = lastCompactionStatus == "loading"
        if store.activeTurnId != nil { feedMascot(.turnStarted(at: now)) }
        feedMascot(.busySessionsChanged(count: busySessions, at: now))
        feedMascot(.pendingInteractionsChanged(count: pendingInteractions, at: now))
        feedMascot(.subagentsChanged(count: runningSubagents, at: now))
        if compactionOpen { feedMascot(.compactionStarted(at: now)) }
    }

    /// `rowId|kind` of the newest row; only the kind drives the activity switch.
    private var mascotActivitySignature: String {
        guard let last = store.timeline.rows.last else { return "|" }
        return "\(last.id)|\(mascotRowTag(last.item))"
    }

    private func mascotRowTag(_ item: TimelineItem) -> String {
        switch item {
        case .reasoning: "reasoning"
        case .toolCall: "toolCall"
        default: "other"
        }
    }

    /// Failed tool calls whose failure is not an AbortError — the machine's `toolFailed`.
    private var failedToolCallIds: [String] {
        store.timeline.rows.compactMap { row in
            if case .toolCall(let call) = row.item, call.status == .failed,
                MascotToolError.isFailure(call)
            {
                return call.callId
            }
            return nil
        }
    }

    /// Running sub-agent tool calls of the followed session.
    private var runningSubagents: Int {
        store.timeline.rows.filter { row in
            if case .toolCall(let call) = row.item, call.status == .running,
                case .subAgent = call.detail
            {
                return true
            }
            return false
        }.count
    }

    /// The raw `status` of the newest compaction row (`loading` / `completed` / unknown), or nil.
    private var lastCompactionStatus: String? {
        store.timeline.rows.compactMap { row -> String? in
            if case .compaction(let status) = row.item { return status }
            return nil
        }.last
    }

    /// Busy sessions in the workspace (the followed one included), as the machine wants them.
    private var busySessions: Int {
        session.agents.filter { $0.status == .running }.count
    }

    /// Workspace-wide pending interactions: approvals, questions, plan reviews.
    private var pendingInteractions: Int {
        session.agents.reduce(0) { $0 + $1.pendingPermissions.count }
    }

    /// Sessions that finished unread while out of view.
    private var attentionCount: Int {
        session.agents.filter { $0.requiresAttention == true }.count
    }

    /// The crab, feet on the composer card's top edge, flush with its right edge, above the card.
    /// 104 × 72 pt of art; only the resting body takes touches.
    @ViewBuilder private var mascotCrab: some View {
        if mascotEnabled {
            ComposerCrab(state: mascot.state)
                .offset(y: -72)
        }
    }

    // MARK: Slash commands (M8a)

    /// Loads the agent's slash commands once per appearance. The store caches them per agent.
    private func loadSlashCommands() async {
        guard slashState == .idle else { return }
        slashState = .loading
        let loaded = await session.hostSettings.loadCommands(for: store.agentId)
        slashCommands = loaded
        slashError = session.hostSettings.commandError(for: store.agentId)
        slashState = .ready
    }

    /// The query while the draft is exactly one slash-command token, else nil.
    private var slashQuery: String? {
        let text = store.draft
        guard text.hasPrefix("/") else { return nil }
        let body = text.dropFirst()
        if body.contains(where: { $0.isWhitespace }) { return nil }
        return String(body)
    }

    private var filteredSlashCommands: [AgentSlashCommand] {
        guard let query = slashQuery, !query.isEmpty else { return slashCommands }
        let lowered = query.lowercased()
        return slashCommands.filter { $0.name.lowercased().hasPrefix(lowered) }
    }

    private var composerPrompt: String {
        if !slashCommands.isEmpty { return "Type / for commands" }
        return store.turns.isEmpty ? "Chat with Paseo" : "Reply to Paseo"
    }

    @ViewBuilder private var slashMenu: some View {
        if slashQuery != nil {
            Group {
                if slashState == .loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading commands…")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let slashError, slashCommands.isEmpty {
                    Text(slashError)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(2)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if filteredSlashCommands.isEmpty {
                    if !slashCommands.isEmpty {
                        Text("No matching commands")
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(filteredSlashCommands) { command in
                                slashCommandRow(command)
                            }
                        }
                    }
                    .frame(maxHeight: 276)
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            .accessibilityIdentifier("composer.slashMenu")
        }
    }

    private func slashCommandRow(_ command: AgentSlashCommand) -> some View {
        Button {
            Haptics.selection()
            store.draft = "/" + command.name + " "
            focused = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("/" + command.name)
                        .font(typography.mono(14, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                    if !command.argumentHint.isEmpty {
                        Text(command.argumentHint)
                            .font(typography.mono(11))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if command.kind == .skill {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .accessibilityLabel("Skill")
                    }
                }
                if !command.description.isEmpty {
                    Text(command.description)
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ["/\(command.name)", command.description]
                .filter { !$0.isEmpty }
                .joined(separator: ", "))
    }

    // MARK: Queue & saved drafts (M8b)

    private var isQueueNonEmpty: Bool {
        !composerQueue.queue(for: store.agentId).isEmpty
    }

    /// The quiet stack of queued messages: ink at secondary emphasis, one line each,
    /// max 3 visible then "+N more"; Edit (back into the draft) and Send now (steers).
    @ViewBuilder private var queueStack: some View {
        let queue = composerQueue.queue(for: store.agentId)
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(queue.messages.prefix(3)) { message in
                    queuedMessageRow(message)
                }
                if queue.count > 3 {
                    Text("+\(queue.count - 3) more")
                        .font(typography.sans(12))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .frame(height: 24)
                        .padding(.leading, 27)
                        .accessibilityLabel("\(queue.count - 3) more queued messages")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func queuedMessageRow(_ message: MessageQueue.QueuedMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ClaudePalette.tertiaryInk)
            Text(message.text)
                .font(typography.sans(14))
                .foregroundStyle(ClaudePalette.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button {
                Haptics.selection()
                editQueuedMessage(message)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit queued message")
            Button {
                Haptics.selection()
                sendQueuedNow(message)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send queued message now")
        }
        .frame(height: 32)
        .padding(.horizontal, 14)
        .contentShape(.rect)
    }

    /// Long-press on the send button: holds the draft back until the running turn ends.
    private func queueDraft() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        composerQueue.mutate(store.agentId) { _ = $0.enqueue(text) }
        store.draft = ""
        QueueHaptics.mediumImpact()
    }

    /// A turn ended: dequeue the head and send it (steers when the next turn is already running).
    /// The in-flight send holds the `isSending` mark until it settles, so an `activeTurnId`
    /// flicker can't fire the same message twice.
    private func flushQueuedMessage() {
        var next: MessageQueue.QueuedMessage?
        composerQueue.mutate(store.agentId) { next = $0.dequeueNext(isIdle: true) }
        guard let next else { return }
        Task {
            await store.send(next.text)
            composerQueue.mutate(store.agentId) { $0.finishSending() }
        }
    }

    /// Moves a queued message back into the draft (replacing it, or appending on a new line).
    private func editQueuedMessage(_ message: MessageQueue.QueuedMessage) {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return }
        if store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.draft = text
        } else {
            store.draft += "\n" + text
        }
        focused = true
    }

    /// Immediate steer of a queued message, cutting the line.
    private func sendQueuedNow(_ message: MessageQueue.QueuedMessage) {
        var taken: String?
        composerQueue.mutate(store.agentId) { taken = $0.take(message.id) }
        guard let text = taken else { return }
        Haptics.send()
        Task { await store.send(text) }
    }

    // MARK: Saved drafts (M8b)

    /// Restores the persisted draft when the conversation opens and the store's draft is empty.
    private func seedSavedDraft() {
        guard store.draft.isEmpty else { return }
        let saved = SavedDraftStore.load(store.agentId)
        if !saved.isEmpty { store.draft = saved }
    }

    /// Debounced write of the draft (~500 ms) to UserDefaults, cleared on send.
    private func scheduleDraftSave(_ value: String) {
        draftSaveTask?.cancel()
        let agentId = store.agentId
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            SavedDraftStore.save(agentId, value)
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            slashMenu
            queueStack
            composerCard
        }
        .padding(.horizontal, focused ? 8 : 16)
        .animation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.feedback), value: focused)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: slashQuery != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isQueueNonEmpty)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.actionError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            TextField(
                "", text: $store.draft,
                prompt: Text(composerPrompt)
                    .foregroundStyle(ClaudePalette.secondaryInk),
                axis: .vertical
            )
            .font(typography.sans(18))
            .lineLimit(1...12)
            .fixedSize(horizontal: false, vertical: true)
            .focused($focused)
            .tint(ClaudePalette.orange)
            .padding(.horizontal, 6)
            .padding(.top, 7)
            .accessibilityIdentifier("composer.draft")
            HStack(spacing: 8) {
                Menu {
                    Button("New agent", systemImage: "plus.bubble") {
                        newAgent(draft: store.draft)
                    }
                    Button("Copy agent ID", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = store.agentId
                        Haptics.selection()
                        showToast("Agent ID copied")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(ClaudePalette.ink)
                        .background(ClaudePalette.chip, in: .circle)
                }
                .accessibilityLabel("Add to agent")
                Button {
                    focused = false
                    sheet = .controls
                } label: {
                    HStack(spacing: 3) {
                        Text(modelChipTitle)
                        if let thinkingLabel {
                            Text(thinkingLabel).foregroundStyle(ClaudePalette.secondaryInk)
                        }
                    }
                    .font(typography.sans(14))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(ClaudePalette.chip, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model, thinking and mode")
                .accessibilityIdentifier("composer.model")
                Spacer(minLength: 0)
                roundButton("mic", label: "Dictate", color: ClaudePalette.chip, ink: ClaudePalette.ink) {
                    focused = true
                }
                .accessibilityIdentifier("composer.dictate")
                if store.isRunning && trimmedDraft.isEmpty {
                    roundButton("stop.fill", label: "Stop response", color: ClaudePalette.ink, ink: ClaudePalette.background) {
                        Task { await store.cancel() }
                    }
                    .accessibilityIdentifier("composer.stop")
                } else {
                    QueueSendButton(
                        isRunning: store.isRunning, canSend: !trimmedDraft.isEmpty
                    ) {
                        send()
                    } onQueue: {
                        queueDraft()
                    }
                    .accessibilityIdentifier("composer.send")
                }
            }
        }
        .padding(8)
        .padding(.top, 1)
        .background(ClaudePalette.composer, in: .rect(cornerRadius: 27))
        .overlay {
            RoundedRectangle(cornerRadius: 27).stroke(ClaudePalette.composerBorder, lineWidth: 0.7)
        }
        .onChange(of: composerFocusRequested.wrappedValue) { _, requested in
            guard requested else { return }
            focused = true
            composerFocusRequested.wrappedValue = false
        }
        // M8b: expand control for tall drafts, left of the crab's spot.
        .overlay(alignment: .topTrailing) { expandComposerButton }
        // The crab stands on the card's top edge, flush with its trailing edge.
        .overlay(alignment: .topTrailing) { mascotCrab }
        .fullScreenCover(isPresented: $showFullScreenComposer) {
            FullScreenComposer(draft: $store.draft, isRunning: store.isRunning) { send() }
        }
    }

    /// M8b: the expand control — visible only when the draft is ~5 lines tall or more.
    @ViewBuilder private var expandComposerButton: some View {
        if DraftMetrics.isTall(store.draft) {
            Button {
                Haptics.selection()
                showFullScreenComposer = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudePalette.secondaryInk)
                    .frame(width: 28, height: 28)
                    .background(ClaudePalette.chip, in: .circle)
            }
            .padding(.trailing, 112)
            .padding(.top, 9)
            .accessibilityLabel("Expand composer")
            .transition(.opacity)
        }
    }

    private var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var modelChipTitle: String {
        modelLabel ?? "Model"
    }

    private var thinkingLabel: String? {
        guard let agent = store.agent, let model = agent.effectiveThinkingOptionId ?? agent.thinkingOptionId else {
            return nil
        }
        guard let modelId = agent.model else { return nil }
        return session.agentControl.thinkingOptions(forProvider: agent.provider, modelId: modelId)
            .first(where: { $0.id == model })?.label
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        SavedDraftStore.clear(store.agentId)
        focused = false
        Haptics.send()
        Task { await store.send(text) }
    }

    private func roundButton(
        _ symbol: String, label: String, color: Color, ink: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(ink)
                .background(color, in: .circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Reads a workspace image through its checkout store (the same instance the panel shares),
    /// for bare absolute/`~` image paths in assistant prose. Returns nil when the workspace of
    /// this conversation isn't open in the directory — those render as path chips.
    private var localImageLoader: ((String) async -> UIImage?)? {
        guard let workspaceId = store.agent?.workspaceId else { return nil }
        let session = self.session
        return { path in
            guard let descriptor = session.workspaceDirectory.workspace(id: workspaceId) else {
                return nil
            }
            let checkout = session.checkout(for: descriptor)
            await checkout.files.read(path, maxBytes: 8 * 1024 * 1024)
            guard checkout.files.phase == .ready,
                let file = checkout.files.file,
                file.kind == .image,
                let content = file.content,
                let data = Data(base64Encoded: content),
                let image = UIImage(data: data)
            else { return nil }
            return image
        }
    }

    private func handleMarkdown(_ action: MarkdownAction) {
        switch action {
        case .openLink(let url):
            openURL(url)
        case .copyCode(let code):
            UIPasteboard.general.string = code
            Haptics.selection()
            showToast("Code copied")
        default:
            break
        }
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { toast = nil }
        }
    }
}

enum ClaudeChatSheet: String, Identifiable {
    case controls
    var id: String { rawValue }
}

/// One turn: your bubble, the process header, the process body, the answer.
struct ClaudeTurnView: View {
    let turn: Turn
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void
    /// Reads a workspace image through the daemon (M5b); nil renders local image paths as chips.
    var localImageLoader: ((String) async -> UIImage?)? = nil
    /// The seqEnd of the match flash this row should paint, if any.
    var highlightedSeq: Int?
    /// The seqEnd of the current match; work groups containing it expand.
    var findTarget: Int?
    /// Called with an absolute path when the reader taps a filename in a Read/Edit/Write row.
    var onOpenFile: ((String) -> Void)?

    /// Nil until the reader taps, so the default can follow the turn's phase.
    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { turn.phase == .running }
    private var isExpanded: Bool { userExpanded ?? isRunning }

    /// The answer stays visible even when the turn folds.
    private var finalProse: TimelineRow? {
        guard !isRunning, case .prose(let row)? = turn.segments.last else { return nil }
        return row
    }

    private var bodySegments: [Turn.Segment] {
        finalProse == nil ? turn.segments : Array(turn.segments.dropLast())
    }

    private var showsHeader: Bool { isRunning || !bodySegments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let row = turn.userMessage, case .userMessage(let message) = row.item {
                ClaudeUserBubble(text: message.text, isPending: row.isPending)
                    .id("row:\(row.seqEnd)")
                    .background(findHighlight(row.seqEnd))
            }
            if showsHeader { header }
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bodySegments) { segment in
                        ClaudeSegmentView(
                            segment: segment, turnIsRunning: isRunning, typography: typography,
                            onMarkdown: onMarkdown, localImageLoader: localImageLoader,
                            highlightedSeq: highlightedSeq, findTarget: findTarget,
                            onOpenFile: onOpenFile)
                    }
                }
                .transition(.opacity.combined(with: .offset(y: -2)))
            }
            if let finalProse, case .assistantMessage(let message) = finalProse.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader)
                    .id("row:\(finalProse.seqEnd)")
                    .background(findHighlight(finalProse.seqEnd))
            }
            if !isRunning, !copyText.isEmpty {
                HStack(spacing: 17) {
                    ClaudeCopyButton(text: copyText, label: "Copy response")
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: turn.phase) { _, phase in
            // A finished turn folds itself away; the answer stays on the page.
            if phase != .running {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { userExpanded = nil }
            }
        }
    }

    /// A brief wash on the matched row; `findHighlight` reads the view's flash parameter.
    private func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(ClaudePalette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
    }

    private var copyText: String {
        var parts: [String] = []
        for segment in turn.segments {
            if case .prose(let row) = segment, case .assistantMessage(let message) = row.item {
                parts.append(message.text)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private var header: some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                userExpanded = !isExpanded
            }
        } label: {
            HStack(spacing: 8) {
                switch turn.phase {
                case .running:
                    ClaudeLiveStatusLine(turn: turn, typography: typography)
                case .completed:
                    Text(turn.duration.map(DurationText.completed) ?? "Completed")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    Spacer(minLength: 0)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(typography.sans(14))
                        .foregroundStyle(ClaudePalette.failureInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                ClaudeChevron(expanded: isExpanded)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "Collapses the work in this turn" : "Shows the work in this turn")
    }
}

/// A segment of a turn.
struct ClaudeSegmentView: View {
    let segment: Turn.Segment
    let turnIsRunning: Bool
    let typography: ClaudeTypography
    let onMarkdown: (MarkdownAction) -> Void
    /// Reads a workspace image through the daemon (M5b); nil renders local image paths as chips.
    var localImageLoader: ((String) async -> UIImage?)? = nil
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch segment {
        case .work(let group):
            ClaudeWorkGroupCell(
                group: group, turnIsRunning: turnIsRunning, typography: typography,
                highlightedSeq: highlightedSeq, findTarget: findTarget, onOpenFile: onOpenFile)
        case .prose(let row):
            if case .assistantMessage(let message) = row.item {
                ClaudeProse(markdown: message.text, typography: typography, onAction: onMarkdown, localImageLoader: localImageLoader)
                    .id("row:\(row.seqEnd)")
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(ClaudePalette.warning.opacity(highlightedSeq == row.seqEnd ? 0.18 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
                    }
            }
        case .todo(let row):
            if case .todo(let list) = row.item { ClaudeTodoCard(list: list) }
        case .notice(let row):
            ClaudeNoticeRow(item: row.item)
        }
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.
struct ClaudeWorkGroupCell: View {
    let group: Turn.WorkGroup
    let turnIsRunning: Bool
    let typography: ClaudeTypography
    var highlightedSeq: Int?
    var findTarget: Int?
    var onOpenFile: ((String) -> Void)?

    @State private var userExpanded: Bool?
    @State private var contentHeight: CGFloat = 0
    @State private var sweepStart = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.claudeProcessCap) private var processCap

    private var opensByDefault: Bool { turnIsRunning && group.isActive }
    private var isExpanded: Bool { userExpanded ?? opensByDefault }

    /// The find target lives in one of this group's rows: expand so it becomes visible.
    private func checkFindTarget() {
        guard let seq = findTarget else { return }
        if group.rows.contains(where: { $0.seqEnd == seq }) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) { userExpanded = true }
        }
    }

    /// The leading seat's activity icon (doc 08 §1.2): the group's content decides the glyph.
    private var seatGlyph: ClaudeGlyph.Kind {
        var hasShell = false
        var hasFile = false
        for row in group.rows {
            if case .toolCall(let call) = row.item {
                switch call.detail {
                case .read, .edit, .write, .search, .fetch:
                    hasFile = true
                default:
                    hasShell = true
                }
            }
        }
        if hasShell { return .api }
        if hasFile { return .browse }
        return .think
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeLeadingSeat(glyph: seatGlyph, expanded: isExpanded)
                    summary
                    Spacer(minLength: 4)
                }
                .frame(minHeight: 17.5) // the counted line: 14 pt × 1.25
                .contentShape(.rect)
            }
            .buttonStyle(ClaudePressButtonStyle())
            .id("group:\(group.rows.first?.seqEnd ?? 0)")
            .onAppear { checkFindTarget() }
            .onChange(of: findTarget) { _, _ in checkFindTarget() }
            .accessibilityLabel(summaryText)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                card
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    /// One sentence of what the group did, such as "Edited 3 files and ran 2 commands". Keeps
    /// DSH's wording; the headline counts folds and tool kinds into verbs. Revised from raw counts.
    private var summaryText: String {
        var editedFiles = Set<String>()
        var readFiles = Set<String>()
        var commands = 0, searches = 0, otherTools = 0
        for row in group.rows {
            guard case .toolCall(let call) = row.item else { continue }
            switch call.detail {
            case .edit(let path, _, _, _), .write(let path, _): editedFiles.insert(path)
            case .read(let path, _): readFiles.insert(path)
            case .shell: commands += 1
            case .search: searches += 1
            default: otherTools += 1
            }
        }
        var parts: [String] = []
        if !editedFiles.isEmpty {
            parts.append("edited \(editedFiles.count) file\(editedFiles.count == 1 ? "" : "s")")
        }
        if commands > 0 {
            parts.append("ran \(commands) command\(commands == 1 ? "" : "s")")
        }
        if !readFiles.isEmpty {
            parts.append("read \(readFiles.count) file\(readFiles.count == 1 ? "" : "s")")
        }
        if searches > 0 {
            parts.append("searched \(searches) time\(searches == 1 ? "" : "s")")
        }
        if otherTools > 0 {
            parts.append("used \(otherTools) other tool\(otherTools == 1 ? "" : "s")")
        }
        if parts.isEmpty { return "Thought" }
        let joined: String
        switch parts.count {
        case 1: joined = parts[0]
        case 2: joined = parts.joined(separator: " and ")
        default:
            joined = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
        guard let first = joined.first else { return "Thought" }
        return String(first).uppercased() + joined.dropFirst()
    }

    private func summaryRuns(_ ink: Color) -> some View {
        Text(summaryText)
            .font(typography.serif(14, weight: .medium))
            .tracking(-0.14)
            .foregroundStyle(ink)
    }

    private var summary: some View {
        Group {
            if turnIsRunning && group.isActive && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    summaryRuns(ClaudePalette.tertiaryInk).overlay(alignment: .leading) {
                        if let phase = ClaudeSweep.phase(startedAt: sweepStart, at: context.date) {
                            summaryRuns(ClaudePalette.shimmerInk)
                                .mask(ClaudeSweep.windowGradient(phase: phase))
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                summaryRuns(ClaudePalette.tertiaryInk)
            }
        }
    }

    private func findHighlight(_ seqEnd: Int) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(ClaudePalette.warning.opacity(highlightedSeq == seqEnd ? 0.18 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: highlightedSeq)
    }

    private var card: some View {
        ScrollView(.vertical) {
            rows
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ClaudeGroupHeightKey.self, value: proxy.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Hugs its rows until they reach the host's cap, then scrolls inside the card.
        .frame(height: min(max(contentHeight, 1), processCap), alignment: .top)
        .onPreferenceChange(ClaudeGroupHeightKey.self) { height in contentHeight = height }
        // The process card is transparent — the canvas shows through.
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
        }
    }

    private var rows: some View {
        let merged = WorkRow.merging(group.rows)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(merged.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Color.clear.frame(height: 4) // the gap above the hairline
                    ClaudeDivider()
                }
                rowView(item, isLive: turnIsRunning && index == merged.count - 1)
            }
        }
    }

    @ViewBuilder private func rowView(_ item: WorkRow, isLive: Bool) -> some View {
        switch item {
        case .thought(let row):
            ClaudeStepRow(row: row, isLive: isLive, typography: typography)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .tool(let row):
            ClaudeStepRow(row: row, isLive: isLive, typography: typography)
                .id("row:\(row.seqEnd)")
                .background(findHighlight(row.seqEnd))
        case .fileCall(let call):
            ClaudeMergedFileRow(
                call: call, isLive: isLive, typography: typography,
                onOpenFile: onOpenFile ?? { _ in },
                highlightedSeq: highlightedSeq, findTarget: findTarget)
                .id(call.id)
        }
    }
}

private struct ClaudeGroupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One thought or tool call inside the process card: one line — 36 pt for thought and file rows,
/// 24 pt for shell/tool rows — a trailing chevron on the disclosure rows, detail below when open.
struct ClaudeStepRow: View {
    let row: TimelineRow
    /// The newest step of a running turn opens by default so you can watch it.
    let isLive: Bool
    let typography: ClaudeTypography

    @State private var userExpanded: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RowKind { case thought, file, tool }

    private var kind: RowKind {
        switch row.item {
        case .reasoning: return .thought
        case .toolCall(let call):
            switch call.detail {
            case .read, .edit, .write: return .file
            default: return .tool
            }
        default: return .tool
        }
    }

    private var isExpanded: Bool { userExpanded ?? isLive }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : .easeOut(duration: ClaudeMotion.move)) {
                    userExpanded = !isExpanded
                }
            } label: {
                HStack(spacing: 6) {
                    label
                    Spacer(minLength: 4)
                    if kind != .tool {
                        ClaudeTurnChevron(expanded: isExpanded)
                    }
                }
                .frame(minHeight: kind == .tool ? 24 : 36)
                .padding(.horizontal, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isExpanded {
                detail
                    .transition(.opacity.combined(with: .offset(y: -2)))
            }
        }
    }

    @ViewBuilder private var label: some View {
        switch row.item {
        case .reasoning(let reasoning):
            if isExpanded {
                Text("Think")
                    .font(typography.serif(13, weight: .medium))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            } else {
                Text(reasoning.text.replacingOccurrences(of: "\n", with: " "))
                    .font(typography.sans(13))
                    .lineSpacing(7) // 13 / 20
                    .foregroundStyle(ClaudePalette.tertiaryInk)
                    .lineLimit(1)
            }
        case .toolCall(let call):
            let presentation = ToolCallPresentation(call)
            if kind == .file {
                HStack(spacing: 0) {
                    Text(presentation.title)
                        .font(typography.sans(13))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    if let subtitle = presentation.subtitle {
                        Circle().fill(ClaudePalette.captionInk).frame(width: 2, height: 2)
                            .padding(.horizontal, 8)
                        Text(subtitle)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .underline(true, pattern: .dot, color: ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ClaudeToolSeat(call: call, symbol: presentation.symbol)
                    Text(presentation.title)
                        .font(typography.serif(13, weight: .medium))
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                    if let subtitle = presentation.subtitle {
                        Circle().fill(ClaudePalette.captionInk).frame(width: 2, height: 2)
                        Text(subtitle)
                            .font(typography.sans(13))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch row.item {
        case .reasoning(let reasoning):
            // The opened thought scrolls with the group and holds no scrollbar of its own.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(reasoningParagraphs(reasoning.text), id: \.self) { paragraph in
                    Text(paragraph)
                        .font(typography.serif(13))
                        .lineSpacing(10) // 13 / 23
                        .foregroundStyle(ClaudePalette.tertiaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
            .padding(.leading, 22)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
        case .toolCall(let call):
            ClaudeToolCallDetail(call: call)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        default:
            EmptyView()
        }
    }

    private func reasoningParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// The leading seat a shell/tool row keeps (doc 08 §1.3(d)): the tool's glyph — the `>-` prompt
/// for a shell call — inside a 16 × 16 box, swapped for a chevron on hover on DSH. Touch has no
/// hover, so the glyph is static here.
private struct ClaudeToolSeat: View {
    let call: ToolCall
    let symbol: String

    var body: some View {
        Group {
            if case .shell = call.detail {
                ClaudeGlyph(kind: .api, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// The leading seat on the summary row (doc 08 §1.2): 16 × 16, the 14 × 14 activity icon at rest;
/// touch has no hover, so the chevron — up while open, down while a finger is down — shows only
/// then. There is no trailing chevron; the chevron lives in the seat.
private struct ClaudeLeadingSeat: View {
    let glyph: ClaudeGlyph.Kind
    let expanded: Bool
    @Environment(\.claudeRowPressed) private var pressed

    var body: some View {
        Group {
            if expanded {
                ClaudeGlyph(kind: .chevronUp, size: 14, color: ClaudePalette.tertiaryInk)
            } else if pressed {
                ClaudeGlyph(kind: .chevronDown, size: 14, color: ClaudePalette.tertiaryInk)
            } else {
                ClaudeGlyph(kind: glyph, size: 14, color: ClaudePalette.tertiaryInk)
            }
        }
        .frame(width: 16, height: 16)
    }
}

#endif
