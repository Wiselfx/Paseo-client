#if canImport(UIKit)
import Observation
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
    ///
    /// W1: held behind a lazy holder. `State(initialValue:)` evaluates its argument every time the
    /// screen's `init` runs, which is every time the shell's body runs, and the controller's init
    /// registers observers, starts a path monitor and writes into the checkout store. Built eagerly,
    /// the shell constructed and threw away a controller per body evaluation (82 to 112 a second at
    /// idle in the first measurement, a feedback loop that held the main thread at 100 %).
    @State private var holder: ChatControllerHolder
    private var controller: ChatController { holder.controller }
    /// The composer's focus (E1 §1): a plain flag, because the composer's field is a
    /// `UITextView` under SwiftUI and nothing focusable is bound to a `@FocusState`.
    @State private var composerFocused = false
    /// The composer field's line limit, from the space this screen offers above the keyboard.
    /// Stored as the line count, so the body runs again only when that number changes (the keyboard
    /// showing or hiding, a rotation, a window resize), never per point of height.
    @State private var composerLineLimit = ComposerFieldLimit.unmeasured

    public init(
        session: HostSession, store: ConversationStore, onOpenSidebar: (() -> Void)? = nil,
        onOpenPanel: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onNewAgent: ((String) -> Void)? = nil, onForkAgent: ((String) -> Void)? = nil,
        onOpenAgent: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        _holder = State(
            initialValue: ChatControllerHolder {
                ChatController(
                    session: session, store: store, onOpenSidebar: onOpenSidebar,
                    onOpenPanel: onOpenPanel, onBack: onBack, onNewAgent: onNewAgent,
                    onForkAgent: onForkAgent, onOpenAgent: onOpenAgent)
            })
    }

    public var body: some View {
        let _ = PaseoPerf.body("ChatScreen")
        let _ = PaseoPerf.why(Self.self)
        // D1 §1: the transcript is the screen's base layer; the chrome floats over it in
        // safe-area bars and the system's scroll edge effect is the only background.
        TranscriptView(store: store, controller: controller)
            // "Back to the end" rides the transcript (J3 §2): the overlay respects the safe area the
            // bottom chrome and the keyboard contribute, so it sits `Space.sm` above the composer (and
            // the subagent pill) and moves with the keyboard and the composer's growth.
            .overlay(alignment: .bottom) {
                TranscriptBackToEndButton(controller: controller)
                    .padding(.bottom, Space.sm)
            }
            // Maximum chat area: no bar anywhere. A short fade keeps the status bar readable, and a
            // blur strip sits under the composer card only (user directive; upstream: none).
            .overlay(alignment: .top) { statusBarFade }
            // Plain safe-area insets, not `safeAreaBar`: a bar hosted the composer twice (two live
            // text views, both updated per keystroke). The blur under the composer is
            // `ComposerUnderBlur`; the transcript draws no system edge of its own.
            .safeAreaInset(edge: .top) { topChrome }
            .safeAreaInset(edge: .bottom) { bottomChrome }
            // No background here: the shell's rounded card (`EdgeDrawerCard`) is the canvas, so
            // the corners stay display-radius when the card is pushed aside (UX-SPEC §1.1).
            .foregroundStyle(Palette.ink)
            .tint(Palette.ink)
            // File links in prose and in your bubbles (`paseo-file://…`) open the file viewer;
            // ordinary links fall through to the host's handler unchanged.
            .modifier(ChatOpenURLWiring(controller: controller))
            .environment(\.chatActions, controller.actions)
            .environment(\.richActions, controller.richActions)
            .modifier(
                ChatInputWiring(store: store, controller: controller, focused: $composerFocused))
            .modifier(
                UserActivityWiring(
                    store: store, controller: controller, focused: $composerFocused))
            .modifier(MascotDriver(store: store, session: session, controller: controller))
            .modifier(ChatSheets(store: store, session: session, controller: controller))
            .onGeometryChange(for: Int.self) { geometry in
                ComposerFieldLimit.lines(availableHeight: geometry.size.height)
            } action: { lines in
                composerLineLimit = lines
            }
            .task {
                // The user-image manifest loads once, off main: bubbles with history
                // reserve their image boxes on the first pass instead of jumping.
                await UserImageCache.shared.ensureManifestLoaded()
            }
            .task {
                // The shared web view for diagrams and SVG cards starts before the first card needs it,
                // not mid-scroll (W1). `WKWebView.init` blocks the main thread while WebKit's content
                // process launches (100 to 700 ms), so the transcript starts it when its open is over
                // (`TranscriptView`, `openPin` ending); this is only the fallback for a chat whose open
                // never ends (a conversation shorter than the screen).
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                RichWebSnapshotRenderer.shared.prewarm()
            }
    }

    // MARK: Chrome

    /// A short fade from the page colour to clear over the status bar, so the clock never sits on
    /// running text. It ends just above the header buttons: the chat keeps the rest of the screen.
    private var statusBarFade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.background, location: 0),
                .init(color: Palette.background, location: 0.55),
                .init(color: Palette.background.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 72)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The top bar: two glass buttons and the centred title. No band, and the find bar joins it
    /// when find is open; content dissolves under them through the scroll edge effect (D1 §1).
    /// The bar reads its own chrome state (find, hidden, sheets), so a flip never rebuilds the
    /// transcript (R-1, H2 §3).
    private var topChrome: some View {
        ChatTopChrome(store: store, controller: controller)
    }

    /// The bottom bar: the subagent pill and the composer, both clear behind their own cards, so
    /// the transcript runs under them (D1 §1). "Back to the end" is an overlay on the transcript.
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            SubagentPill(store: store, controller: controller)
            ComposerView(
                mode: .conversation, store: store, controller: controller,
                focused: $composerFocused, fieldLineLimit: composerLineLimit)
        }
        .background(alignment: .bottom) { ComposerUnderBlur() }
    }
}
/// The old name, kept so the shell and the rest of the app compile unchanged (ticket: a
/// `public typealias` is fine if the screen is renamed).
public typealias ClaudeChatView = ChatScreen
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
