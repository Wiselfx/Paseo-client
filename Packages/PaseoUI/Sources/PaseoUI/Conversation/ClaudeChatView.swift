#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    /// M7h fork: called with the new agent's id after "Fork from here" creates it; the shell
    /// navigates to it. Nil hides the fork affordance.
    var onForkAgent: ((String) -> Void)?
    /// M7i hero seats: open a freshly created agent (workspace chip). Nil disables the seat.
    var onOpenAgent: ((String) -> Void)?

    let typography = ClaudeTypography()

    @State var sheet: ClaudeChatSheet?
    @State var toast: String?
    @FocusState var focused: Bool
    /// One-shot "focus the composer" signal from the shell (e.g. after "Mention in chat").
    @Environment(\.composerFocusRequested) var composerFocusRequested
    // Find in conversation (M7 §2). The transcript owns the scroll; `store.search` owns the matches.
    @State var findOpen = false
    @State var findQuery = ""
    @State var findIndex = 0
    @State var findFlash: Int?
    @State var findAnchor: String?
    @State var findSearchTask: Task<Void, Never>?
    @State var scrollProxy: ScrollViewProxy?
    /// The last turn row that appeared; the find restore anchors to it.
    @State var lastTrackedTurn: String?
    @FocusState var findFocused: Bool
    // Chat-follow (M7b §1).
    @State var isFollowing = true
    /// M7d chat-anchor: armed when a message is sent; the transcript pins it to the top until
    /// the answer grows past the bottom, when tail-follow takes over again.
    @State var anchoringToAnswer = false
    @State var composerHeight: CGFloat = 0
    /// One quiet line per permission answer made this session; the store drops resolved
    /// requests without remembering the answer, so the client keeps the record.
    @State var permissionResolvedLines: [AnsweredPermission] = []
    /// Provider subagents hidden via "Archive finished"; app-side only, in memory, this session.
    @State var hiddenSubagentIds: Set<String> = []
    /// A file tapped from a Read/Edit/Write row; presented as the existing Files viewer in a sheet.
    @State var openFilePath: String?
    /// M7d rewind: a scope awaiting the can't-undo confirmation dialog (messageId + chosen scope).
    @State var pendingRewind: PendingRewind?
    /// True while a confirmed rewind RPC is in flight; double-taps on the confirm button no-op.
    @State var rewindInFlight = false
    /// M7h message actions: the one awaiting confirmation (Edit/Rerun rewind on confirm).
    @State var pendingMessageAction: PendingMessageAction?
    /// M7i turn rail: shown while scrolling (and hides shortly after), never always-on.
    @State var turnNavVisible = false
    @State var turnNavIdleTask: Task<Void, Never>?
    // Header title menu (M7 §1).
    @State var renamingAgent = false
    @State var renameText = ""
    @State var archiveAgentConfirm = false
    @Environment(\.openURL) var openURL
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    /// M5a: the DSH crab above the composer, driven by the conversation's turns.
    @AppStorage(PaseoSettingsKeys.mascot) var mascotEnabled = true
    /// M8c: what tap does on send while a turn is running (steer | queue | interrupt).
    @AppStorage(DefaultSendBehavior.storageKey) var defaultSend = DefaultSendBehavior.steer.rawValue
    @State var mascot = MascotStateMachine()
    /// Failed tool calls we've already told the mascot about, by `callId`.
    @State var signalledToolFailureIds: Set<String> = []
    /// Whether the machine has been told a compaction is open (edge detection for rows).
    @State var compactionOpen = false
    /// Baseline for the rising edge so an existing badge doesn't fire on appear.
    @State var attentionActive = false
    /// M8a: slash commands for this agent (`/` at the start of the draft opens the menu).
    @State var slashCommands: [AgentSlashCommand] = []
    @State var slashState: SlashCommandState = .idle
    @State var slashError: String?
    /// M8b: the queue for this agent, kept app-side so it survives switching agents.
    @State var composerQueue = ComposerQueueStore.shared
    /// M8b: the full-height editor for long drafts (expand control in the card's top-right).
    @State var showFullScreenComposer = false
    /// M8e: context meter tap → the details sheet (wired to `store.contextUsage`).
    @State var showContextSheet = false
    /// M8b: debounce for saved-draft writes (~500 ms).
    @State var draftSaveTask: Task<Void, Never>?
    /// M6a: attachments for this conversation, app-scope so they survive agent switches.
    @State var attachmentStore = ComposerAttachmentStore.shared
    @State var photoSelection: [PhotosPickerItem] = []
    @State var showCameraPicker = false
    @State var showFileImporter = false
    @State var showForgePicker = false
    @State var attachmentViewerImage: UIImage?
    /// M8d: @-mentions of workspace files.
    @State var mentionIndex = MentionIndex()
    @State var mentionDebounce: Task<Void, Never>?
    @State var mentionMatches: [MentionIndexRow] = []
    /// Paths picked this session; they rank first in the popover.
    @State var recentMentions: [String] = []
    /// M8d: on-device dictation into the draft.
    @State var dictation = DictationController()

    enum SlashCommandState {
        case idle, loading, ready
    }

    public init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onOpenPanel: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil, onForkAgent: ((String) -> Void)? = nil,
        onOpenAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        self.onOpenSidebar = onOpenSidebar
        self.onOpenPanel = onOpenPanel
        self.onBack = onBack
        self.onNewAgent = onNewAgent
        self.onForkAgent = onForkAgent
        self.onOpenAgent = onOpenAgent
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
        // File links in prose and in your bubbles (`paseo-file://…`) open the file viewer;
        // ordinary links fall through to the host's handler unchanged.
        .environment(\.openURL, fileLinkAction)
        .overlay(alignment: .bottom) { backToEnd }
        .sheet(item: $sheet) { item in
            switch item {
            case .controls:
                ClaudeAgentControlsSheet(session: session, store: store)
            case .subagents:
                ChatSubagentsSheet(
                    subagents: store.subagents, typography: typography,
                    hiddenIds: $hiddenSubagentIds)
            case .backgroundWork:
                ChatBackgroundWorkSheet(backgroundWork: store.backgroundWork, typography: typography)
            case .turnNav:
                ChatTurnNavSheet(turns: store.turns, currentTurnId: lastTrackedTurn) { id in
                    sheet = nil
                    jumpToTurn(id)
                }
            }
        }
        .sheet(isPresented: $showContextSheet) {
            ClaudeContextSheet(store: store)
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
        .onAppear { dictation.onDraft = { [weak store] text in store.draft = text } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dictation.stop(keepingDraft: true) }
        }
        .task { await loadSlashCommands() }
        .onChange(of: store.activeTurnId) { oldId, newId in
            if newId == nil, oldId != nil { flushQueuedMessage() }
            if newId == nil {
                // The turn ended: the anchor's job (hold your message at the top while the
                // answer arrives) is done; hand back to the normal follow rules.
                anchoringToAnswer = false
                isFollowing = true
            }
        }
        .onChange(of: store.draft) { _, newValue in
            scheduleDraftSave(newValue)
        }
        .onChange(of: mentionQuery) { _, query in
            mentionDebounce?.cancel()
            if query != nil {
                Task { await loadMentionIndexIfNeeded() }
                mentionDebounce = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let query = mentionQuery else { return }
                    mentionMatches = mentionIndex.matches(query: query, recent: recentMentions)
                }
            } else {
                mentionMatches = []
            }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            handlePickedPhotos(items)
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
}
#endif
