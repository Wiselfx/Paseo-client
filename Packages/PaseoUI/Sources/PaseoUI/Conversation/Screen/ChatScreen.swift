#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One agent's conversation, rendered from `ConversationStore.turns` in ClaudeUI's clothes.
///
/// Layout follows `docs/research/06-dsh-ux-spec.md` §1 (turn structure, the counted work group,
/// the 36 pt process rows) and §2 (the live status line), on top of the M2 seam in
/// `docs/research/07-claudeui-adoption-map.md` §5.4.
///
/// R6: this body reads **no** store or session property except identity. Everything else lives in
/// the child structs, each of which reads only what it draws — typing re-evaluates the composer,
/// streaming re-evaluates the last turn row and the status line.
public struct ChatScreen: View {
    let session: HostSession
    @Bindable var store: ConversationStore

    /// Everything that is not a SwiftUI handle. Created once per open agent (the shell applies
    /// `.id(agentId)`, so a switch builds a fresh screen and a fresh controller).
    @State private var controller: ChatController
    /// The composer's focus (E1 §1): a plain flag, because the composer's field is a
    /// `UITextView` under SwiftUI and nothing focusable is bound to a `@FocusState`.
    @State private var composerFocused = false
    @Environment(\.toast) private var toast
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onOpenPanel: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil, onForkAgent: ((String) -> Void)? = nil,
        onOpenAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        _controller = State(
            initialValue: ChatController(
                session: session, store: store, onOpenSidebar: onOpenSidebar,
                onOpenPanel: onOpenPanel, onBack: onBack, onNewAgent: onNewAgent,
                onForkAgent: onForkAgent, onOpenAgent: onOpenAgent))
    }

    public var body: some View {
        // D1 §1: the transcript is the screen's base layer; the chrome floats over it in
        // safe-area bars and the system's scroll edge effect is the only background.
        TranscriptView(store: store, controller: controller)
            // "Back to the end" rides the transcript, not the composer bar (J3 §2). The bar lives
            // in `.safeAreaBar(edge: .bottom)`, whose host does not hit-test outside the bar's own
            // frame, so a touch on a button pushed above it landed on the transcript underneath
            // and only dropped the keyboard. An overlay on the transcript is inside its own
            // hit-testable frame, and it respects the safe area the bottom bar and the keyboard
            // contribute, so it sits `Space.sm` above the bar (and above the subagent pill),
            // moving with the keyboard and with the composer's growth. No inset arithmetic.
            .overlay(alignment: .bottom) {
                TranscriptBackToEndButton(controller: controller)
                    .padding(.bottom, Space.sm)
            }
            .safeAreaBar(edge: .top) { topChrome }
            .safeAreaBar(edge: .bottom) { bottomChrome }
            .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
            // No background here: the shell's rounded card (`EdgeDrawerCard`) is the canvas, so
            // the corners stay display-radius when the card is pushed aside (UX-SPEC §1.1).
            .foregroundStyle(Palette.ink)
            .tint(Palette.ink)
            // File links in prose and in your bubbles (`paseo-file://…`) open the file viewer;
            // ordinary links fall through to the host's handler unchanged.
            .environment(\.openURL, controller.fileLinkAction(host: openURL))
            .environment(\.chatActions, controller.actions)
            .environment(\.richActions, controller.richActions)
            .modifier(
                ChatInputWiring(store: store, controller: controller, focused: $composerFocused))
            .modifier(
                UserActivityWiring(
                    store: store, controller: controller, focused: $composerFocused))
            .modifier(MascotDriver(store: store, session: session, controller: controller))
            .modifier(ChatSheets(store: store, session: session, controller: controller))
            .onAppear {
                controller.toastCenter = toast
                controller.reduceMotion = reduceMotion
                controller.openURLFromEnvironment = { url in openURL(url) }
                // The user-image manifest loads once, off main: bubbles with history
                // reserve their image boxes on the first pass instead of jumping.
                Task { await UserImageCache.shared.ensureManifestLoaded() }
            }
            .onChange(of: reduceMotion) { _, value in controller.reduceMotion = value }
            .onChange(of: toast.map(ObjectIdentifier.init)) { _, _ in controller.toastCenter = toast }
    }

    // MARK: Chrome

    /// The top bar: two glass buttons and the centred title. No band, and the find bar joins it
    /// when find is open; content dissolves under them through the scroll edge effect (D1 §1).
    /// The bar reads its own chrome state (find, hidden, sheets), so a flip never rebuilds the
    /// transcript (R-1, H2 §3).
    private var topChrome: some View {
        ChatTopChrome(store: store, controller: controller)
    }

    /// The bottom bar: the subagent pill and the composer, both clear behind their own cards, so
    /// the transcript runs under them (D1 §1). "Back to the end" is **not** here: it is an overlay
    /// on the transcript, because a `safeAreaBar` host does not hit-test outside its own frame
    /// (J3 §2, `ChatScreen`).
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            SubagentPill(store: store, controller: controller)
            ComposerView(
                mode: .conversation, store: store, controller: controller,
                focused: $composerFocused)
        }
    }
}

/// The old name, kept so the shell and the rest of the app compile unchanged (ticket: a
/// `public typealias` is fine if the screen is renamed).
public typealias ClaudeChatView = ChatScreen

// MARK: - Wiring

/// The draft, the queue and the turn boundary: things that change while you type or while the
/// agent works. A modifier's body is its own value in the graph, so a keystroke re-evaluates this
/// and the composer's text field — not the transcript.
struct ChatInputWiring: ViewModifier {
    let store: ConversationStore
    let controller: ChatController
    @Binding var focused: Bool

    /// Inline images decode at the screen's width in pixels; `UIScreen.main` is deprecated on
    /// iOS 26, so the scale comes from the environment (D1 §4).
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .task { await controller.loadSlashCommands() }
            .onChange(of: store.activeTurnId) { oldId, newId in
                guard newId == nil, oldId != nil else { return }
                // The anchor's job (hold your message at the top while the answer arrives) is
                // done. Clearing it first lets a queued message arm its own runway.
                controller.anchoringToAnswer = false
                controller.flushQueuedMessage()
                // Follow comes back from the transcript's idle rule, not from here: the reader
                // may have scrolled away from the end while the answer ran.
            }
            .draftObserver(
                store: store,
                onDraftChange: { newValue in
                    controller.scheduleDraftSave(newValue)
                    controller.feedMascot(.userActivity(at: Date()))
                },
                onMentionQueryChange: { query in controller.handleMentionQuery(query) })
            .onAppear {
                controller.seedSavedDraft()
                controller.displayScale = displayScale
                controller.dictation.onDraft = { [store] text in store.draft = text }
            }
            .onChange(of: displayScale) { _, scale in controller.displayScale = scale }
    }
}

/// Toast notices and the turn-finished haptic: neither is drawn by this screen.
struct UserActivityWiring: ViewModifier {
    let store: ConversationStore
    let controller: ChatController
    @Binding var focused: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: store.lastNotice?.message) { _, message in
                guard let message else { return }
                controller.showToast(message)
                store.clearNotice()
            }
            .onChange(of: store.isRunning) { wasRunning, isRunning in
                if wasRunning && !isRunning { Haptics.settle() }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    controller.feedMascot(.userActivity(at: Date()))
                    controller.requestEndScroll()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                controller.dictation.stop(keepingDraft: true)
                // M15: voice mode stops cleanly in the background (mic + wake lock off).
                controller.voiceEngine.stopCapture()
                if controller.session.voiceSession.isVoiceMode {
                    Task { await controller.session.voiceSession.stop() }
                }
            }
    }
}

/// Watches the composer's text in a body of its own (P3).
///
/// `.onChange(of: store.draft)` placed on the conversation's root view subscribed that whole
/// body to the draft, so every keystroke re-evaluated the header, the transcript's turns and the
/// turn rail. A view modifier's body is a separate value in the graph: reading the draft here
/// re-evaluates this modifier and the text field, and nothing else.
struct DraftObserver: ViewModifier {
    let store: ConversationStore
    let onDraftChange: (String) -> Void
    let onMentionQueryChange: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: store.draft) { _, newValue in onDraftChange(newValue) }
            .onChange(of: mentionQuery) { _, query in onMentionQueryChange(query) }
    }

    /// The open mention query for the current draft; nil when there is none.
    private var mentionQuery: String? { ChatMentions.query(in: store.draft) }
}

extension View {
    func draftObserver(
        store: ConversationStore, onDraftChange: @escaping (String) -> Void,
        onMentionQueryChange: @escaping (String?) -> Void
    ) -> some View {
        modifier(
            DraftObserver(
                store: store, onDraftChange: onDraftChange,
                onMentionQueryChange: onMentionQueryChange))
    }
}
#endif
