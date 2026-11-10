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
    @FocusState private var focused: Bool
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
        ClaudeFontResources.register()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ChatHeaderBar(store: store, controller: controller)
            if controller.find.isOpen {
                ChatFindBarView(store: store, controller: controller)
            }
            TranscriptView(store: store, controller: controller)
            SubagentPill(store: store, controller: controller)
            ComposerView(
                mode: .conversation, store: store, controller: controller, focused: $focused)
        }
        // No background here: the shell's rounded card (`EdgeDrawerCard`) is the canvas, so the
        // corners stay display-radius when the card is pushed aside (UX-SPEC §1.1).
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
        // File links in prose and in your bubbles (`paseo-file://…`) open the file viewer;
        // ordinary links fall through to the host's handler unchanged.
        .environment(\.openURL, controller.fileLinkAction(host: openURL))
        .environment(\.chatActions, controller.actions)
        .modifier(ChatInputWiring(store: store, controller: controller, focused: $focused))
        .modifier(UserActivityWiring(store: store, controller: controller, focused: $focused))
        .modifier(MascotDriver(store: store, session: session, controller: controller))
        .modifier(ChatSheets(store: store, session: session, controller: controller))
        .onAppear {
            controller.toastCenter = toast
            controller.reduceMotion = reduceMotion
            controller.openURLFromEnvironment = { url in openURL(url) }
        }
        .onChange(of: reduceMotion) { _, value in controller.reduceMotion = value }
        .onChange(of: toast.map(ObjectIdentifier.init)) { _, _ in controller.toastCenter = toast }
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
    @FocusState.Binding var focused: Bool

    func body(content: Content) -> some View {
        content
            .task { await controller.loadSlashCommands() }
            .onChange(of: store.activeTurnId) { oldId, newId in
                guard newId == nil, oldId != nil else { return }
                controller.flushQueuedMessage()
                // The anchor's job (hold your message at the top while the answer arrives) is
                // done; hand back to the normal follow rules.
                controller.anchoringToAnswer = false
                controller.isFollowing = true
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
                controller.dictation.onDraft = { [store] text in store.draft = text }
            }
    }
}

/// Toast notices and the turn-finished haptic: neither is drawn by this screen.
struct UserActivityWiring: ViewModifier {
    let store: ConversationStore
    let controller: ChatController
    @FocusState.Binding var focused: Bool

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
