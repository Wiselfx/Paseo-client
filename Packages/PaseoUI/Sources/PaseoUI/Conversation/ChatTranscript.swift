#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension ClaudeChatView {
    // MARK: Transcript

    @ViewBuilder var content: some View {
        VStack(spacing: 0) {
            if store.turns.isEmpty, store.pendingPermissions.isEmpty {
                switch store.phase {
                case .loading:
                    Spacer()
                    ProgressView()
                    Spacer()
                case .failed(let message):
                    emptyState(title: "Couldn't load agent history", detail: message)
                case .ready:
                    VStack(spacing: 4) {
                        ClaudeHomeHero(hint: nil)
                        ClaudeHeroSeats(
                            session: session, store: store, onOpenAgent: onOpenAgent)
                    }
                }
            } else {
                transcript
            }
        }
        // Opening the conversation is deliberate focus: refresh the track list now (list events
        // aren't replayed), exactly like a reconnect does.
        .task {
            await store.subagents.load()
            await store.backgroundWork.load()
        }
        .confirmationDialog(
            messageActionTitle,
            isPresented: Binding(
                get: { pendingMessageAction != nil },
                set: { if !$0 { pendingMessageAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingMessageAction
        ) { action in
            Button(action.kind == .edit ? "Rewind and edit" : "Rewind and rerun", role: .destructive) {
                pendingMessageAction = nil
                Task { await performMessageAction(action) }
            }
            Button("Cancel", role: .cancel) { pendingMessageAction = nil }
        } message: { action in
            Text(messageActionDescription(for: action))
        }
    }

    /// The subagents track: one quiet pill in the strip directly above the composer, where
    /// upstream puts its `ComposerTrackBar` pills (`app/src/panels/agent-tracks.tsx:127`,
    /// `SubagentsTrack` over both row kinds). Nil when nothing is tracked, or every provider row
    /// was hidden this session.
    @ViewBuilder var subagentPill: some View {
        if !visibleSubagents.isEmpty || !managedSubagents.isEmpty {
            SubagentTrackPill(items: visibleSubagents, managed: managedSubagents) {
                sheet = .subagents
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Paseo-managed children of the open agent: ordinary agents labelled with its id.
    var managedSubagents: [AgentSnapshot] {
        session.subagents(of: store.agentId)
    }

    /// Rows the pill and sheet show; "Archive finished" hides every non-running row this session.
    var visibleSubagents: [ProviderSubagent] {
        store.subagents.items.filter { !hiddenSubagentIds.contains($0.id) }
    }

    func emptyState(title: String, detail: String?) -> some View {
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

    /// One turn row, split out of `transcript` so the type checker sees it on its own.
    func turnView(_ turn: Turn, index: Int) -> some View {
        let canFork = session.isForkContextSupportedByHost && onForkAgent != nil
        // The turn's own prompt, and the row above it — where DSH cuts for Retract and for
        // Delete this turn (`message-cut.ts`: the host has no in-place truncate).
        let userRow = turn.userMessage
        let cutRow = userRow.flatMap(boundaryBefore)
        let canCut = canFork && cutRow != nil
        let fork: ((ClaudeForkTarget, TimelineRow) async -> Void)? =
            canFork ? { target, row in await forkInto(target, boundary: row.seqEnd) } : nil
        let forkInFlight: ((ClaudeForkTarget) async -> Void)? =
            canFork ? { target in await forkInto(target, boundary: nil) } : nil
        return ClaudeTurnView(
            turn: turn, typography: typography,
            onMarkdown: handleMarkdown, localImageLoader: localImageLoader,
            highlightedSeq: findFlash,
            findTarget: findSeq,
            onOpenFile: { path in openFileViewer(at: path) },
            rewindChoices: rewindMenuScopes,
            onRewind: { scope, messageId in
                pendingRewind = PendingRewind(messageId: messageId, scope: scope)
            },
            canRewrite: canRewrite,
            onEdit: { messageId, text in
                pendingMessageAction = PendingMessageAction(messageId: messageId, text: text, kind: .edit)
            },
            onRerun: { messageId, text in
                pendingMessageAction = PendingMessageAction(messageId: messageId, text: text, kind: .rerun)
            },
            onFork: fork,
            onForkInFlight: forkInFlight,
            onDeleteTurn: canCut ? { row in deleteTurn(userRow: row) } : nil,
            onRetract: canCut ? { row in retractMessage(userRow: row) } : nil,
            isLatestTurn: index == store.turns.count - 1
        )
    }

    var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 27) {
                        ForEach(Array(store.turns.enumerated()), id: \.element.id) { index, turn in
                            turnView(turn, index: index)
                            .id(turn.id)
                            .onAppear {
                                lastTrackedTurn = turn.id
                                visibleTurnIds.insert(turn.id)
                                reportReadingPosition()
                            }
                            .onDisappear { visibleTurnIds.remove(turn.id) }
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
                        if store.backgroundWork.hasRunningItems {
                            BackgroundWorkRow(items: store.backgroundWork.items) {
                                Haptics.selection()
                                sheet = .backgroundWork
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .scrollPosition($scrollPosition)
                .scrollDismissesKeyboard(.interactively)
                // Older history loads itself; the only affordance is this spinner at the top,
                // overlaid so appearing/disappearing never moves the content (UX spec §4.3).
                .overlay(alignment: .top) {
                    if store.isLoadingOlder {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Loading earlier messages")
                    }
                }
                .overlay(alignment: .bottom) { transcriptFade }
                .overlay(alignment: .trailing) { outlineRail }
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
                    anchoringToAnswer = false
                    if findOpen {
                        closeFind()
                        return
                    }
                    isFollowing = true
                    scrollToBottom(proxy, animated: false)
                }
                // Chat-anchor (M7d): when your message appears (pending send), pin it to the top
                // of the viewport and let the answer grow below it — instead of the tail-follow
                // pushing it off the top.
                .onChange(of: pendingRowSignature) { _, _ in
                    anchorToSentMessage(proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    isFollowing = true
                    if !findOpen { scrollToBottom(proxy, animated: false) }
                    reportReadingPosition()
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
                        distanceFromTop: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        offsetY: geometry.contentOffset.y,
                        viewportHeight: geometry.bounds.height)
                } action: { _, metrics in
                    if transcriptHeight != metrics.viewportHeight {
                        transcriptHeight = metrics.viewportHeight
                    }
                    // A prepended page moved the content down by its own height; put the reader
                    // back before anything else reacts to the new offsets.
                    if restoreHistoryAnchor(metrics) { return }
                    reportReadingPosition()
                    revealTurnRail()
                    loadOlderIfNeeded(metrics)
                    if anchoringToAnswer {
                        // While anchored, the message stays pinned to the top; only once the
                        // growing content overflows the viewport does tail-follow take over.
                        if metrics.distanceFromBottom > 16 {
                            anchoringToAnswer = false
                            isFollowing = true
                        }
                        return
                    }
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

    func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Ids of the pending user-message rows, for the anchor's send detection.
    var pendingRowSignature: String {
        store.timeline.rows.lazy.filter(\.isPending).map(\.id).joined(separator: "|")
    }

    /// Scopes the rewind menu shows: host feature gate + the provider's advertised flags, verbatim.
    var rewindMenuScopes: [RewindScope] {
        guard session.isRewindSupportedByHost else { return [] }
        return store.rewindCapabilities.menu
    }

    /// The intercepted openURL action: paseo-file links open the workspace file viewer (absolute
    /// paths made workspace-relative), everything else falls through to the host's action.
    var fileLinkAction: OpenURLAction {
        let hostOpenURL = openURL
        return OpenURLAction { url in
            if let path = FilePathLinks.path(from: url) {
                openFileViewer(at: fileLinkDisplayPath(path))
                return .handled
            }
            // Forward to the host's action (Safari sheet, system browser…); it decides.
            hostOpenURL(url)
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

    /// Pins the pending send to the top of the viewport (M7d chat-anchor). Only while a row is
    /// still pending; once the daemon confirms it (or drops a failed send) the anchor holds the
    /// position by itself and stops re-pinning.
    func anchorToSentMessage(_ proxy: ScrollViewProxy) {
        guard anchoringToAnswer, !pendingRowSignature.isEmpty else { return }
        let newest = store.timeline.rows.last(where: {
            if case .userMessage = $0.item { return true } else { return false }
        })
        guard let newest else {
            anchoringToAnswer = false
            return
        }
        let target = "row:\(newest.seqEnd)"
        if reduceMotion {
            proxy.scrollTo(target, anchor: .top)
        } else {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .top) }
        }
    }

    /// Scope used by Edit/Rerun (M7h): prefer conversation-only rewind; fall back to both.
    /// Nil when the provider can't rewind the conversation — the actions hide.
    var rewriteScope: RewindScope? {
        let scopes = rewindMenuScopes
        return scopes.contains(.conversation) ? .conversation : (scopes.contains(.both) ? .both : nil)
    }

    var canRewrite: Bool { rewriteScope != nil }

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

    /// Runs the confirmed action: Edit rewinds and returns the text to the composer; Rerun
    /// rewinds and resends the same text.
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

    /// Forks the conversation into the chosen target and opens the new agent.
    ///
    /// `boundary` nil is the in-flight fork: the daemon then projects the whole timeline, the
    /// partially streamed answer included (upstream `turn-footer.tsx:38-46`).
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

    /// Retract: fork before the message, then hand the text back in the new session's composer
    /// (DSH `message-actions.ts:197-207`).
    func retractMessage(userRow: TimelineRow) {
        guard let boundary = boundaryBefore(userRow), case .userMessage(let message) = userRow.item
        else { return }
        Task {
            await openForkedAgent(
                await store.forkConversation(fromBoundarySeq: boundary),
                toast: "The message is back in the composer", draft: message.text)
        }
    }

    /// Delete this turn: fork before the turn's prompt and keep the prefix only (DSH
    /// `message-actions.ts:231-236`).
    func deleteTurn(userRow: TimelineRow) {
        guard let boundary = boundaryBefore(userRow) else { return }
        Task {
            await openForkedAgent(
                await store.forkConversation(fromBoundarySeq: boundary),
                toast: "The turn is absent from the new session")
        }
    }

    /// The projected row directly above `row` — the fork boundary for a cut "before this
    /// message". Nil when the row is the first in the timeline (nothing to keep).
    func boundaryBefore(_ row: TimelineRow) -> Int? {
        let rows = store.timeline.rows
        guard let index = rows.firstIndex(where: { $0.id == row.id }), index > 0 else { return nil }
        return rows[index - 1].seqEnd
    }

    /// Creates the workspace "Fork in a new workspace" lands in, through the sidebar's create
    /// path (`WorkspaceDirectory.createWorkspace`) with the values the new-workspace sheet
    /// prefills: a worktree cut off the project's checkout branch. Upstream opens its
    /// new-workspace form here and hands the fork's history to it as a draft
    /// (`use-fork-agent.ts:181-196`); our sheet seeds an agent with a plain prompt, so the fork
    /// creates the workspace and then the agent itself.
    func createForkWorkspace() async -> String? {
        let directory = session.workspaceDirectory
        guard let agent = store.agent, let workspaceId = agent.workspaceId,
            let workspace = directory.workspace(id: workspaceId),
            let project = directory.projects.first(where: { $0.projectId == workspace.projectId })
        else {
            // Upstream `message.actions.forkMissingWorkspace` (en.ts:338).
            showToast("This agent is not in a workspace.")
            return nil
        }
        if !directory.supportsWorkspaceCreate {
            showToast("This daemon cannot create worktree workspaces.")
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

    /// The branch a fork's worktree cuts from: the project's local (non-worktree) checkout, else
    /// any branch the directory carries, else "main". Same rule as `ClaudeNewWorkspaceSheet`.
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

    /// One place for the tail every fork shares: surface the failure, refresh the sidebar, say
    /// what happened, open the new agent. An optional `draft` seeds its composer.
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

    /// Runs the confirmed rewind and toasts the outcome. One confirm in flight at a time.
    func performPendingRewind(_ rewind: PendingRewind) {
        guard !rewindInFlight else { return }
        rewindInFlight = true
        Task {
            let failure = await store.rewind(toMessageId: rewind.messageId, scope: rewind.scope)
            rewindInFlight = false
            if let failure {
                showToast(failure)
            } else {
                // The timeline is truncated away from the rewound point; resume tail-follow.
                anchoringToAnswer = false
                isFollowing = true
                showToast("Rewound")
            }
        }
    }

    struct ScrollFollowMetrics: Equatable {
        var distanceFromBottom: CGFloat
        /// Offset below the top of the content. 0 at the very top.
        var distanceFromTop: CGFloat
        var contentHeight: CGFloat
        var offsetY: CGFloat
        var viewportHeight: CGFloat
    }

    /// Where the viewport sat when an older page was requested, so the prepend can be undone.
    struct HistoryAnchor: Equatable {
        var contentHeight: CGFloat
        var offsetY: CGFloat
        /// The start cursor at request time; unchanged means the page prepended nothing.
        var cursor: TimelineCursor?
        var startedAt: Date
        /// The growth already compensated; a correction is re-applied only when the content
        /// grows further, so the reader can scroll freely right after a page lands.
        var appliedGrowth: CGFloat = 0
    }

    /// Older history loads itself: no "Load earlier" row and no button. While the top of the
    /// transcript is within about one screen of the viewport, the next page is fetched; the
    /// prepend is compensated so the reader's place does not move (UX spec §4.3).
    func loadOlderIfNeeded(_ metrics: ScrollFollowMetrics) {
        guard !historyLoadInFlight, store.timeline.hasOlder, !store.isLoadingOlder else { return }
        guard metrics.distanceFromTop <= metrics.viewportHeight else { return }
        historyLoadInFlight = true
        let cursor = store.timeline.startCursor
        historyAnchor = HistoryAnchor(
            contentHeight: metrics.contentHeight, offsetY: metrics.offsetY, cursor: cursor,
            startedAt: Date())
        Task {
            await store.loadOlder()
            historyLoadInFlight = false
            // Nothing was prepended (an empty or failed page): there is nothing to anchor.
            if let anchor = historyAnchor, store.timeline.startCursor == anchor.cursor {
                historyAnchor = nil
            }
        }
    }

    /// Undoes a prepend by scrolling down by the height the content above the viewport grew.
    /// Returns true when it scrolled, so the rest of the geometry handler can be skipped.
    ///
    /// The correction is absolute and repeats while the anchor lives: a lazy stack can report the
    /// prepended height over more than one layout pass, and re-applying converges instead of
    /// leaving the reader short. The anchor expires so a later tail growth can never reuse it.
    func restoreHistoryAnchor(_ metrics: ScrollFollowMetrics) -> Bool {
        guard let anchor = historyAnchor else { return false }
        if Date().timeIntervalSince(anchor.startedAt) > 2 {
            historyAnchor = nil
            return false
        }
        let growth = metrics.contentHeight - anchor.contentHeight
        if growth > 1, abs(growth - anchor.appliedGrowth) > 1 {
            historyAnchor?.appliedGrowth = growth
            scrollPosition.scrollTo(y: anchor.offsetY + growth)
            return true
        }
        if !historyLoadInFlight { historyAnchor = nil }
        return false
    }

    /// The 40 pt fade band: the transcript melts into the canvas just above the composer.
    var transcriptFade: some View {
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
    @ViewBuilder var backToEnd: some View {
        if !findOpen && !isFollowing {
            Button {
                Haptics.selection()
                anchoringToAnswer = false
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
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.bottom, composerHeight + 7)
            .transition(.opacity)
            .accessibilityIdentifier("transcript.backToEnd")
            .accessibilityLabel("Back to the end")
        }
    }

    /// U5: the prompt rail — every prompt of the conversation as a tick at the trailing edge,
    /// drawn over the transcript with no reserved margin. It appears while scrolling and for a
    /// moment after; its 24 pt touch strip is live while it shows.
    @ViewBuilder var outlineRail: some View {
        let items = outlineItems
        if case .ready = store.phase, items.count >= ChatOutlineRail.minimumPrompts {
            ChatOutlineRail(
                items: items,
                activeSeq: store.promptOutline.activeSeq,
                viewportHeight: transcriptHeight,
                isRevealed: turnNavVisible,
                onJump: { seq in jumpToPrompt(seq) },
                onReveal: { revealTurnRail() })
            .transition(.opacity)
        }
    }

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

    /// The timeline position under the top of the viewport: the first row of the topmost turn the
    /// lazy stack has mounted. Turns appear as they approach the viewport, so the earliest mounted
    /// turn is the one the reader is inside or just below.
    func reportReadingPosition() {
        var seq = store.turns.first(where: { visibleTurnIds.contains($0.id) })?.firstRowSeq
        if seq == nil, isFollowing { seq = outlineItems.last?.seq }
        store.promptOutline.reportReadingPosition(anchorSeq: seq)
    }

    /// Scroll-reveals the rail and keeps it up briefly; hidden again shortly after scrolling stops.
    func revealTurnRail() {
        guard outlineItems.count >= ChatOutlineRail.minimumPrompts else { return }
        if !turnNavVisible { turnNavVisible = true }
        turnNavIdleTask?.cancel()
        turnNavIdleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            turnNavVisible = false
        }
    }

    /// A rail tick or a sheet row: a loaded prompt scrolls there now; an unloaded one fetches just
    /// its window first (the store's `jump(toPromptSeq:)`), then scrolls.
    func jumpToPrompt(_ seq: Int) {
        isFollowing = false
        Task {
            guard let rowId = await store.jump(toPromptSeq: seq) else { return }
            jumpToTurn(rowId)
        }
    }

    /// Jumps the transcript to `id` (a turn view id). Reduce Motion jumps without animation.
    func jumpToTurn(_ id: String) {
        guard let proxy = scrollProxy else { return }
        // Jumping backwards releases the tail-follow, like M7b.
        isFollowing = false
        if reduceMotion {
            proxy.scrollTo(id, anchor: .top)
        } else {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    func resolvedPermissionLine(_ text: String) -> some View {
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
}
/// The timeline position of a turn's first row, for the outline's reading-position report. A turn
/// without a leading user message (rewinds, streamed tails) starts at its first segment row.
private extension Turn {
    var firstRowSeq: Int? {
        if let row = userMessage { return row.seqStart }
        for segment in segments {
            switch segment {
            case .work(let group):
                if let row = group.rows.first { return row.seqStart }
            case .prose(let row), .todo(let row), .notice(let row):
                return row.seqStart
            }
        }
        return nil
    }
}
#endif
