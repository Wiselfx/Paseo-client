#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's timeline.
///
/// SwiftUI builds the content as values (`TranscriptModel`: one `TurnRow` per turn plus the trailing
/// cards) and measures the bars; `TranscriptEngine` owns the `UICollectionView` that shows them and
/// every scroll rule: following the tail, the send, "Back to the end", older history, jumps and find.
///
/// **Reads:** `store.turns`, the trailing cards' emptiness, `store.phase` (states), `controller.find`
/// (open/match/flash), `controller.actions.availability`, `store.canceledTurnIds`, and the landing line.
/// **Writes** (through the engine, only when a boundary flips): `controller.isFollowing`,
/// `controller.backToEnd`, `controller.headerHidden`.
struct TranscriptView: View {
    @Bindable var store: ConversationStore
    let controller: ChatController

    /// The landing line's fade (`turn-nav.css:155-194`).
    static let landingDuration: TimeInterval = 1.4
    /// How long the rail stays up after the last scroll frame.
    static let turnNavIdleDuration: TimeInterval = 1.5
    /// Upstream's fixed history-start slot (strategy-native.tsx:69-74).
    static let historyStartSlotHeight: CGFloat = 32
    /// Turns warmed ahead of the first render.
    static let warmupTurns = 16

    @State private var engine = TranscriptEngine()
    /// The transcript's height with the keyboard down (E3b): rich media and the process cap read it,
    /// so the keyboard's arrival never resizes every capped block. Grows for one width; a width change
    /// resets it.
    @State private var stableViewportHeight: CGFloat = 0
    @State private var stableViewportWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.shellDrawer) private var shellDrawer
    @Environment(\.toast) private var toast
    @Environment(\.codeSizeStep) private var codeSizeStep
    @Environment(\.surfaceFlags) private var surfaceFlags
    @Environment(\.artifactZoomNamespace) private var artifactZoom

    var body: some View {
        let _ = PaseoPerf.body("Transcript")
        let model = makeModel()
        GeometryReader { proxy in
            TranscriptCollectionHost(
                engine: engine, store: store, controller: controller, model: model,
                environment: cellEnvironment(width: proxy.size.width, height: proxy.size.height),
                insets: proxy.safeAreaInsets
            )
            .ignoresSafeArea()
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            updateStableViewport(size)
        }
        .overlay {
            if showsStates { states }
        }
        .overlay(alignment: .trailing) {
            TranscriptRail(store: store, controller: controller, engine: engine)
        }
        .onChange(of: controller.find.isOpen) { _, isOpen in
            if isOpen { engine.findOpened() } else { engine.findClosed() }
        }
        .onChange(of: controller.find.jump) { _, jump in
            guard let jump else { return }
            controller.find.jump = nil
            engine.scrollToMatch(jump)
        }
        .onChange(of: controller.pendingJump) { _, jump in
            guard let jump else { return }
            controller.pendingJump = nil
            engine.jumpToTurn(jump.id)
        }
        .onChange(of: controller.endScrollRequest) { _, _ in engine.endScrollRequested() }
        .onChange(of: controller.sendEndRequest) { _, _ in engine.followEndAfterSend() }
        .onChange(of: controller.jumpToEndRequest) { _, _ in engine.returnToEnd() }
        .onChange(of: engine.ui.turnNavVisible) { _, shown in
            shellDrawer?.trailingEdgeReserved = shown
        }
        .onAppear { shellDrawer?.trailingEdgeReserved = engine.ui.turnNavVisible }
        .onDisappear { shellDrawer?.trailingEdgeReserved = false }
        // The newest turns' prose is split, parsed and highlighted off the main actor before their
        // first render (`ProseWarmup`).
        .task(id: store.turns.isEmpty) {
            guard !store.turns.isEmpty else { return }
            ProseWarmup.startForOpen(store: store, limit: Self.warmupTurns)
        }
        // Opening the conversation is deliberate focus: refresh the track list now (list events
        // aren't replayed), exactly like a reconnect does.
        .task {
            await store.subagents.load()
            await store.backgroundWork.load()
        }
    }

    /// The content as values. O(turns) with cheap comparisons: unchanged turns share storage, so
    /// the engine's equality checks stop at the first field.
    private func makeModel() -> TranscriptModel {
        let turns = store.turns
        let lastId = turns.last?.id
        let findSeq = controller.find.isOpen ? controller.find.rowSeq : nil
        let flashSeq = controller.find.isOpen ? controller.find.flash : nil
        let availability = controller.actions.availability
        let actions = controller.actions
        let landing = engine.ui.landingTurnId
        let canceled = store.canceledTurnIds
        var model = TranscriptModel()
        model.items.reserveCapacity(turns.count + 4)
        model.entries.reserveCapacity(turns.count + 4)
        model.items.append(.historyStart)
        model.entries.append(.historyStart)
        for turn in turns {
            model.items.append(.turn(turn.id))
            model.entries.append(
                .turn(
                    TurnRow(
                        turn: turn,
                        availability: availability,
                        isLatest: turn.id == lastId,
                        findSeq: findSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                        flashSeq: flashSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                        isLanding: turn.id == landing,
                        actions: actions,
                        isCanceled: turn.turnId.map { canceled.contains($0) } ?? false)))
        }
        if !store.pendingPermissions.isEmpty {
            model.items.append(.permissions)
            model.entries.append(.permissions)
        }
        if !store.permissionResolvedLines.isEmpty {
            model.items.append(.resolvedPermissions)
            model.entries.append(.resolvedPermissions)
        }
        if store.backgroundWork.hasRunningItems {
            model.items.append(.backgroundWork)
            model.entries.append(.backgroundWork)
        }
        return model
    }

    private func cellEnvironment(width: CGFloat, height: CGFloat) -> TranscriptCellEnvironment {
        TranscriptCellEnvironment(
            store: store,
            controller: controller,
            history: engine.history,
            engine: engine,
            rowFrames: engine.rowFrames,
            openURL: engine.openURL(for: controller),
            column: max(width - 2 * TranscriptLayout.sideMargin, 0),
            viewport: stableViewportHeight > 0 ? stableViewportHeight : height,
            toast: toast,
            shellDrawer: shellDrawer,
            surfaceFlags: surfaceFlags,
            codeSizeStep: codeSizeStep,
            artifactZoom: artifactZoom,
            dynamicType: String(describing: dynamicTypeSize))
    }

    /// Keyboard-independent viewport height: the keyboard and a growing composer only shrink the
    /// transcript, and ignoring a shrink keeps every cap fixed through focus changes.
    private func updateStableViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if abs(size.width - stableViewportWidth) >= 1 {
            stableViewportWidth = size.width
            stableViewportHeight = size.height
        } else if size.height - stableViewportHeight >= 1 {
            stableViewportHeight = size.height
        }
    }

    /// Loading, empty or failed: nothing in the transcript to show. O(1), two emptiness checks.
    private var showsStates: Bool {
        store.turns.isEmpty && store.pendingPermissions.isEmpty
    }

    /// Loading, empty and failed states, a whole viewport tall so a centred state stays centred.
    private var states: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch store.phase {
                case .loading:
                    LoadingState()
                case .failed(let message):
                    VStack(spacing: 0) {
                        InlineBanner(
                            .failure, title: message, systemImage: "exclamationmark.triangle",
                            action: ("Try again", { Task { await store.load() } }))
                            .padding(16)
                        Spacer(minLength: 0)
                    }
                case .ready:
                    // An existing agent with nothing in it is not a new session (audit C #22).
                    EmptyState(systemImage: nil, title: "No messages yet")
                }
            }
            .containerRelativeFrame(.vertical)
        }
        .scrollDisabled(true)
        .simultaneousGesture(TapGesture().onEnded { controller.dismissKeyboard() })
    }
}

/// Hands the model, the cell environment and the bars' insets to the engine.
private struct TranscriptCollectionHost: UIViewRepresentable {
    let engine: TranscriptEngine
    let store: ConversationStore
    let controller: ChatController
    let model: TranscriptModel
    let environment: TranscriptCellEnvironment
    let insets: EdgeInsets

    func makeUIView(context: Context) -> TranscriptContainerView {
        engine.attach(store: store, controller: controller)
        return engine.container
    }

    func updateUIView(_ uiView: TranscriptContainerView, context: Context) {
        engine.update(model: model, environment: environment)
        engine.setInsets(insets, animation: context.transaction.animation)
    }
}

/// U5: the prompt rail, over the transcript's trailing edge while scrolling. Its own body, so a
/// streamed token never re-evaluates it.
private struct TranscriptRail: View {
    let store: ConversationStore
    let controller: ChatController
    let engine: TranscriptEngine

    var body: some View {
        if ChatOutlineRail.promptRailEnabled, case .ready = store.phase, controller.outlineAvailable {
            GeometryReader { proxy in
                ChatOutlineRail(
                    items: controller.outlineItems,
                    activeSeq: store.promptOutline.activeSeq,
                    viewportHeight: proxy.size.height,
                    isRevealed: engine.ui.turnNavVisible,
                    onJump: { seq in controller.jumpToPrompt(seq) },
                    onReveal: { engine.revealTurnRail() })
            }
            .transition(.opacity)
        }
    }
}

/// "Back to the end": offered once you are more than a screen from the end of the content
/// (D1 §3). It fades and scales in from 0.9 through `Motion.fade`, and tapping it turns follow
/// back on at once. Hidden, it stays in place, so nothing else can move when it comes and goes.
///
/// It is hosted by the **transcript**, as an `.overlay(alignment: .bottom)` (J3 §2). It used to
/// hang above the composer bar through `.overlay(alignment: .top)` on `bottomChrome`, pushed out
/// with `.alignmentGuide(.top)`; the bar is itself hosted by `.safeAreaBar(edge: .bottom)`, whose
/// host does not hit-test outside the bar's own frame, so every touch on the circle landed on the
/// transcript underneath (which only drops the keyboard) and the button looked dead.
///
/// On the transcript, the overlay respects the safe area the bottom bar and the keyboard
/// contribute, so the button sits `Space.sm` above the bar — and above the subagent pill — moves
/// with the keyboard and with the composer's growth, and needs no inset arithmetic. The old
/// placement padded the scroll view's overlay by `geometry.contentInsets.bottom`, which the bottom
/// `safeAreaBar` already contributes to the scroll view's frame, so the composer (and the keyboard)
/// was counted twice.
struct TranscriptBackToEndButton: View {
    let controller: ChatController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shows = controller.showsBackToEnd && !controller.find.isOpen
        Button {
            controller.returnToEnd()
        } label: {
            Image(systemName: "arrow.down")
                .font(.glyph(.regular, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .frame(width: 44, height: 44)
                .background(Palette.panel, in: .circle)
                .overlay {
                    Circle().strokeBorder(Palette.cardBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(BackToEndPressStyle())
        .opacity(shows ? 1 : 0)
        .scaleEffect(shows ? 1 : 0.9)
        .allowsHitTesting(shows)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: shows)
        .accessibilityHidden(!shows)
        .accessibilityIdentifier("transcript.backToEnd")
        .accessibilityLabel("Back to the end")
    }
}

/// Touch-down answers on the back-to-end circle: it scales in on `Motion.feedback` like the
/// rest of the app's buttons, and Reduce Motion switches instantly.
struct BackToEndPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}

/// DSH's landing line: a 2 pt ink rule over the turn a jump just landed on, fading in and out
/// over `TranscriptView.landingDuration` (`turn-nav.css:155-194`). UX-SPEC §0.1 forbids orange as
/// state, so it is ink. Reduce Motion shows it standing for the same time, without the fade.
struct LandingLine: View {
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Rectangle().fill(Palette.ink).frame(height: 2)
            } else {
                TimelineView(.animation) { context in
                    let (opacity, scaleX) = phase(at: context.date)
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(height: 2)
                        .scaleEffect(x: CGFloat(scaleX), y: 1, anchor: .center)
                        .opacity(opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `0% opacity 0 scaleX .5 → 25% opacity 1 scaleX 1 → 70% opacity 1 → 100% opacity 0`.
    func phase(at date: Date) -> (opacity: Double, scaleX: Double) {
        let t = date.timeIntervalSince(startedAt) / TranscriptView.landingDuration
        if t <= 0 { return (0, 0.5) }
        if t < 0.25 {
            let k = t / 0.25
            return (k, 0.5 + 0.5 * k)
        }
        if t < 0.7 { return (1, 1) }
        if t < 1 { return (1 - (t - 0.7) / 0.3, 1) }
        return (0, 1)
    }
}

/// The daemon-confirmed resolution lines (D8), factored out of the transcript body:
/// this small view reads `pendingPermissions` and the store's answered lines,
/// so a permission change re-evaluates only this view — never the transcript (R-1).
struct ResolvedPermissionLines: View {
    @Bindable var store: ConversationStore

    var body: some View {
        let pendingIds = Set(store.pendingPermissions.map(\.id))
        let confirmed = store.permissionResolvedLines.filter { !pendingIds.contains($0.id) }
        if !confirmed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(confirmed) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.glyph(.small))
                        Text(item.line)
                            .font(.paseo(.caption))
                    }
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(item.line)
                }
            }
            .transition(.opacity)
        }
    }
}

#endif
