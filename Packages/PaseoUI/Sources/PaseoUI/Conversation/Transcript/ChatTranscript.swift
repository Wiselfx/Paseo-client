#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's timeline, and the only view that owns a scroll handle.
///
/// **Reads:** `store.turns`, `store.pendingPermissions`, `store.phase`, `store.backgroundWork`,
/// `store.isLoadingOlder`, `store.promptOutline` (rail + reading position), `controller.find`
/// (open/seq/flash), `controller.isFollowing` / `anchoringToAnswer`, `controller.outlineItems`
/// (rail), `controller.landingTurnId`, `controller.endScrollRequest` / `jumpToEndRequest` (the
/// composer's wish and the button's order). It reads `store.timeline` only for the pending-row
/// signature (one dictionary-free pass over the ids while a send is pending).
///
/// **Writes:** `controller.isFollowing`, `controller.anchoringToAnswer`, `controller.backToEnd`
/// and `controller.headerHidden`, each only when its boundary flips — never per scroll frame. The
/// signed scroll travel and the top visible turn stay in `TranscriptScrollTrack`, which nothing
/// observes.
struct TranscriptView: View {
    @Bindable var store: ConversationStore
    let controller: ChatController

    /// Turn-nav motion constants, ported from DSH's `turn-nav.ts` / `turn-nav.css`.
    static let glideLead: CGFloat = 480
    /// The gap between rows in the transcript's stack, and the runway's arithmetic depends on it.
    static let turnSpacing: CGFloat = 27
    /// What the stack itself keeps under the tail turn: the row gap before the end marker, the
    /// marker itself and the bottom padding. The runway is the empty room you can see, so it must
    /// not count them (D1 §2).
    static let runwaySlack: CGFloat = turnSpacing + 1 + 20
    /// The glide's duration (`easeScrollFor`'s short glide).
    static let glideDuration: TimeInterval = 0.3
    /// The landing line's fade (`turn-nav.css:155-194`).
    static let landingDuration: TimeInterval = 1.4
    /// How long the rail stays up after the last scroll frame.
    static let turnNavIdleDuration: TimeInterval = 1.5
    /// The reading-position report's throttle while scrolling.
    static let readingReportInterval: TimeInterval = 0.1

    /// U3: scroll position, used to undo the jump a prepended history page would cause, and to
    /// lead a long jump.
    @State private var scrollPosition = ScrollPosition()
    /// Where the viewport sat when an older page was requested; nil when nothing is pending.
    @State private var historyAnchor: HistoryAnchor?
    /// One older-page fetch at a time, driven by the top of the transcript.
    @State private var historyLoadInFlight = false
    /// The transcript's viewport height, for the outline rail's slot math.
    @State private var transcriptHeight: CGFloat = 0
    /// Turns the lazy stack has mounted (reading position) and the last one that appeared.
    @State private var scrollTrack = TranscriptScrollTrack()
    /// M7i turn rail: shown while scrolling (and hides shortly after), never always-on.
    @State private var turnNavVisible = false
    /// The turn a jump just landed on, for the landing line; nil once its fade is done.
    @State private var landingTurnId: String?
    @State private var landingStartedAt = Date()
    /// The second half of a glide-lead: the instant lead has landed, so the rest glides.
    @State private var pendingGlide: PendingGlide?
    /// A jump to a row that had never been laid out, measuring its offset before leading.
    @State private var pendingLeadJump: PendingLeadJump?
    /// The last throttled reading-position / rail tick, so a scroll frame does O(1) work.
    @State private var lastRailTick = Date.distantPast
    /// True while a finger, a flick or the deceleration owns the transcript. A plain `Bool`
    /// written at phase boundaries only: the phase itself lives in `TranscriptScrollTrack`, so a
    /// scroll frame never invalidates the body.
    @State private var scrollHeld = false
    /// The send runway (D1 §2). One `@State`, written on layout, never per scroll frame.
    @State private var runway = SendRunway()
    /// The transcript's height with the keyboard down (E3b). Rich media and the process cap read
    /// it, so the keyboard's arrival never resizes every capped block while the user types. It
    /// only grows for one width and resets when the width changes (rotation, split view).
    @State private var stableViewportHeight: CGFloat = 0
    @State private var stableViewportWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellDrawer) private var shellDrawer

    var body: some View {
        content
            // A turn arrived. If you just sent it, the runway opens and it glides to the top.
            .onChange(of: store.turns.last?.id) { _, id in beginRunway(for: id) }
            // The anchor's job is done. At the anchor this trims nothing; if the reader scrolled
            // away while the answer ran, the idle rule already removed the room below the screen.
            .onChange(of: controller.anchoringToAnswer) { _, anchoring in
                if !anchoring { trimRunwayIfNeeded() }
            }
            .onAppear { shellDrawer?.trailingEdgeReserved = turnNavVisible }
            .onChange(of: turnNavVisible) { _, shown in
                shellDrawer?.trailingEdgeReserved = shown
            }
            // Leaving the transcript hands the trailing edge back to the panel.
            .onDisappear { shellDrawer?.trailingEdgeReserved = false }
            // Opening the conversation is deliberate focus: refresh the track list now (list
            // events aren't replayed), exactly like a reconnect does.
            .task {
                await store.subagents.load()
                await store.backgroundWork.load()
            }
            // Tapping a message, a bubble or the transcript's background drops the keyboard, the
            // way Claude does (V5 §2). Simultaneous, so a link, a menu, a long-press preview and
            // text selection all still get their tap.
            .simultaneousGesture(TapGesture().onEnded { controller.dismissKeyboard() })
    }

    @ViewBuilder private var content: some View {
        if store.turns.isEmpty, store.pendingPermissions.isEmpty {
            states
        } else {
            transcript
        }
    }

    /// Loading, empty and failed states in a scroll view of their own, so the chrome attaches the
    /// same way as it does over the transcript and the first turns arriving move nothing (D1 §1).
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
            // A whole viewport tall, so a centred state stays centred.
            .containerRelativeFrame(.vertical)
        }
        .scrollDisabled(true)
    }

    private var transcript: some View {
        GeometryReader { geometry in
            // The keyboard shrinks `geometry`: the first pass has no stable value yet, so it uses
            // this pass's real height; after that only a width change or real growth moves it.
            let viewport = stableViewportHeight > 0 ? stableViewportHeight : geometry.size.height
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Self.turnSpacing) {
                        turns
                        pendingPermissionCards
                        resolvedPermissionLines
                        backgroundWorkRow
                        // The send runway lives inside the end marker, so it costs no row gap of
                        // its own and the resting layout is unchanged when there is none.
                        Color.clear.frame(height: 1 + runway.height).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .coordinateSpace(name: TranscriptScrollTrack.contentSpace)
                }
                .scrollPosition($scrollPosition)
                .scrollDismissesKeyboard(.interactively)
                // Opening the conversation lands at the bottom; growth at the tail keeps it
                // pinned while following, and the reader's line stays put when not.
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(followAnchor, for: .sizeChanges)
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
                .overlay(alignment: .trailing) { outlineRail }
                .onChange(of: controller.find.isOpen) { _, isOpen in
                    if isOpen { restoreFindAnchor() } else { restoreScroll(proxy: proxy) }
                }
                .onChange(of: controller.find.jump) { _, jump in
                    guard let jump else { return }
                    controller.find.jump = nil
                    scrollToRow(jump.seq, animated: jump.animated, proxy: proxy)
                }
                .onChange(of: controller.pendingJump) { _, jump in
                    guard let jump else { return }
                    controller.pendingJump = nil
                    jumpToTurn(jump.id, proxy: proxy)
                }
                .onChange(of: controller.endScrollRequest) { _, _ in
                    endScrollRequested()
                }
                .onChange(of: controller.jumpToEndRequest) { _, _ in
                    withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                }
                .onAppear { reportReadingPosition() }
                .onScrollPhaseChange { _, phase in
                    scrollTrack.phase = phase
                    // Only the boundary invalidates the body: the size-change anchor may move.
                    let held: Bool
                    switch phase {
                    case .interacting, .tracking, .decelerating: held = true
                    default: held = false
                    }
                    if scrollHeld != held { scrollHeld = held }
                    switch phase {
                    case .interacting, .tracking, .decelerating, .animating:
                        revealTurnRail()
                    case .idle:
                        // A flick that reached the end settles with no further geometry change;
                        // every chrome decision belongs to this edge, never to a frame.
                        scrollSettled()
                    @unknown default:
                        reportReadingPosition()
                    }
                    // J3 §3: a programmatic glide that reaches the end ("Back to the end", or the
                    // tap-to-end wish) does not always land on the scroll view's own end: an
                    // animated `ScrollPosition.scrollTo(edge: .bottom)` can stop at the edge of
                    // the readable area, and a glide that grows nothing produces no geometry
                    // change, so no `.idle` settle ever re-ran the decision and the button stayed
                    // up over the last message. `.animating` is the programmatic glide leaving:
                    // decide once here, with every frame of that glide already in the metrics.
                    if previous == .animating { decideBackToEnd() }
                }
                .onScrollGeometryChange(for: ScrollFollowMetrics.self) { geometry in
                    ScrollFollowMetrics(
                        // `contentInsets.bottom` is the composer: measured from the end of the
                        // content you can actually see, so 0 is the end and negative is past it.
                        distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y
                            - geometry.bounds.height + geometry.contentInsets.bottom,
                        // J3 §3: the reader's own distance — the end of the content to the bottom
                        // of the content area. `contentInsets.bottom` and the content height
                        // cancel, so this value does not move when the keyboard or a tall composer
                        // only takes room from the view: `contentOffset.y + bounds.height` is the
                        // same number before and after.
                        distanceFromContentBottom: geometry.contentSize.height
                            - geometry.contentOffset.y - geometry.bounds.height
                            + geometry.contentInsets.bottom,
                        distanceFromTop: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        offsetY: geometry.contentOffset.y,
                        viewportHeight: geometry.bounds.height,
                        visibleHeight: geometry.bounds.height - geometry.contentInsets.top
                            - geometry.contentInsets.bottom)
                } action: { previous, metrics in
                    handleScroll(metrics, from: previous, proxy: proxy)
                }
                .environment(\.claudeProcessCap, min(400, viewport * 0.5))
                // Rich cards cap media at 60 %/70 % of the transcript's own height (E3b).
                .environment(\.richViewportHeight, viewport)
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                updateStableViewport(size)
            }
        }
    }

    /// Keyboard-independent viewport height. The keyboard and a growing composer both only
    /// shrink the transcript; ignoring a shrink keeps every cap (and the process cap) fixed
    /// through focus changes. A width change is a real resize and resets both axes.
    private func updateStableViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if abs(size.width - stableViewportWidth) >= 1 {
            stableViewportWidth = size.width
            stableViewportHeight = size.height
        } else if size.height - stableViewportHeight >= 1 {
            stableViewportHeight = size.height
        }
    }

    /// While following, tail growth pins to the bottom with no animation; while anchored to a
    /// just-sent message (or reading back), the top stays put (M7d). While a finger or a
    /// deceleration owns the scroll, growth never fights it, so the anchor is the top (D1 §3).
    private var followAnchor: UnitPoint {
        guard !scrollHeld else { return .top }
        return controller.isFollowing && !controller.anchoringToAnswer ? .bottom : .top
    }

    // MARK: Rows

    @ViewBuilder private var turns: some View {
        // One read of the tail id, before the loop: a turn never scans the list to know it is last.
        let lastId = store.turns.last?.id
        // Find inputs are computed per row only while find is open; otherwise both are nil and no
        // turn scans its rows.
        let findSeq = controller.find.isOpen ? controller.findSeq : nil
        let flashSeq = controller.find.isOpen ? controller.find.flash : nil
        // One read of the turn-action value for every row: it changes when the agent or host
        // capabilities change, not per turn, and `TurnRow` compares it (E3 §2).
        let availability = controller.actions.availability
        ForEach(store.turns) { turn in
            TurnRow(
                turn: turn,
                availability: availability,
                isLatest: turn.id == lastId,
                findSeq: findSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                flashSeq: flashSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                isLanding: turn.id == landingTurnId,
                actions: controller.actions
            )
            .equatable()
            .id(turn.id)
            .onAppear {
                scrollTrack.turnAppeared(turn.id, seq: turn.firstRowSeq)
                reportReadingPosition()
            }
            .onDisappear {
                scrollTrack.turnDisappeared(turn.id)
                reportReadingPosition()
            }
            // Content-space offset: the reading-position anchor and the jump lead both read it
            // O(1). It changes on layout, not while scrolling.
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .named(TranscriptScrollTrack.contentSpace)).minY
            } action: { minY in
                scrollTrack.turnOffsetChanged(turn.id, offset: minY)
            }
            // The send runway is measured off the tail turn alone (D1 §2). Every turn's height is
            // recorded in the track: the tail can report before the runway is opened for it and
            // the ordering must not decide the runway's first frame (H2 §1).
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                scrollTrack.turnHeightChanged(turn.id, height: height)
                updateRunway(turnId: turn.id, height: height)
            }
        }
    }

    @ViewBuilder private var pendingPermissionCards: some View {
        if !store.pendingPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.pendingPermissions) { request in
                    ClaudePermissionCard(request: request, store: store) { answered in
                        store.recordAnsweredPermission(answered)
                    }
                }
            }
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion),
                value: store.pendingPermissions.count)
        }
    }

    /// The resolution lines (D8): an answer renders only after the daemon confirms
    /// it — the request disappearing from `pendingPermissions` (by a resolution
    /// event or a snapshot refresh). Until then the card owns the pending state.
    /// A small child view reads the confirmation state, so a permission change
    /// never re-evaluates the transcript's body (R-1).
    @ViewBuilder private var resolvedPermissionLines: some View {
        ResolvedPermissionLines(store: store)
    }

    @ViewBuilder private var backgroundWorkRow: some View {
        if store.backgroundWork.hasRunningItems {
            BackgroundWorkRow(items: store.backgroundWork.items) {
                controller.sheet = .backgroundWork
            }
        }
    }

    // MARK: Scroll

    private func handleScroll(
        _ metrics: ScrollFollowMetrics, from previous: ScrollFollowMetrics, proxy: ScrollViewProxy
    ) {
        if transcriptHeight != metrics.viewportHeight {
            transcriptHeight = metrics.viewportHeight
        }
        scrollTrack.contentOffset = metrics.offsetY
        scrollTrack.distanceFromBottom = metrics.distanceFromBottom
        scrollTrack.distanceFromContentBottom = metrics.distanceFromContentBottom
        scrollTrack.contentHeight = metrics.contentHeight
        if scrollTrack.visibleHeight != metrics.visibleHeight {
            scrollTrack.visibleHeight = metrics.visibleHeight
            runwayViewportChanged()
        }
        openRunwayIfPossible(proxy: proxy)
        // The second half of a glide-lead: the instant jump has landed, so the last stretch
        // glides (DSH `turn-nav.ts:412-474`).
        if let glide = pendingGlide {
            pendingGlide = nil
            withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                proxy.scrollTo(glide.id, anchor: .top)
            }
        }
        // A jump to a row that had never been laid out measured its offset by landing on it; take
        // the last stretch back, then glide from there.
        if let pending = pendingLeadJump {
            pendingLeadJump = nil
            let targetY = scrollTrack.offset(of: pending.id) ?? metrics.offsetY
            let distance = targetY - pending.fromOffset
            guard abs(distance) > Self.glideLead else { return }
            let leadY = targetY - (distance > 0 ? Self.glideLead : -Self.glideLead)
            pendingGlide = PendingGlide(id: pending.id)
            scrollPosition.scrollTo(y: leadY)
            return
        }
        // A prepended page moved the content down by its own height; put the reader back before
        // anything else reacts to the new offsets.
        if restoreHistoryAnchor(metrics) { return }
        // The per-frame work stays O(1); the reading position and the rail are throttled (R6 §4).
        let now = Date()
        if now.timeIntervalSince(lastRailTick) >= Self.readingReportInterval {
            lastRailTick = now
            reportReadingPosition()
            revealTurnRail()
        }
        loadOlderIfNeeded(metrics)
        updateHeaderReveal(metrics, from: previous)
        releaseFollowWhileDragging(metrics)
        // "Back to the end" flips only when the content itself moved. An inset-only frame is what
        // the keyboard animates, and it must never flash the button (H2 §2, J3 §3).
        if backToEndMayFlip,
            metrics.distanceFromContentBottom != previous.distanceFromContentBottom
        {
            decideBackToEnd()
        }
    }

    /// The scroll came to rest: the one edge where chrome state is allowed to change. The follow,
    /// button and anchor decisions run on the distance the gesture left behind, before the trim
    /// below changes the range.
    private func scrollSettled() {
        reportReadingPosition()
        handOverAnchorIfFilled()
        followIfAtEnd()
        decideBackToEnd()
        closeRunwayAtRest()
    }

    /// The follow state machine (D1 §3). While the finger is down it may only turn follow off,
    /// when the reader drags away from the end; turning it back on belongs to the settle.
    private func releaseFollowWhileDragging(_ metrics: ScrollFollowMetrics) {
        guard case .interacting = scrollTrack.phase else { return }
        guard metrics.distanceFromBottom > Self.followSlack else { return }
        if controller.isFollowing { controller.isFollowing = false }
        if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
    }

    /// A runway that is gone means the answer fills the screen: the tail takes over.
    private func handOverAnchorIfFilled() {
        guard controller.anchoringToAnswer, runway.measured, runway.height <= 0,
            scrollTrack.distanceFromBottom <= Self.followSlack
        else { return }
        controller.anchoringToAnswer = false
        controller.isFollowing = true
    }

    /// Tail-follow turns on only from a settled scroll at the end.
    private func followIfAtEnd() {
        guard !controller.isFollowing, !controller.anchoringToAnswer else { return }
        guard scrollTrack.distanceFromBottom <= Self.followSlack else { return }
        guard case .idle = scrollTrack.phase else { return }
        controller.isFollowing = true
    }

    /// "Back to the end" is offered only once the reader is more than a screen from the end of the
    /// content. The screen is the keyboard-independent viewport — the sliver above the keyboard is
    /// not one — and the distance is the content's own, without the composer or the keyboard inset
    /// in it (J3 §3), so focusing the composer can never flash the button.
    private func decideBackToEnd() {
        var state = controller.backToEnd
        state.update(
            distanceFromContentBottom: scrollTrack.distanceFromContentBottom,
            screen: stableViewportHeight > 0 ? stableViewportHeight : scrollTrack.visibleHeight,
            isFollowing: controller.isFollowing)
        if controller.backToEnd != state { controller.backToEnd = state }
    }

    /// The button's visibility is decided on user motion and at rest, never while the scroll view
    /// animates (a programmatic glide) and never on an inset-only frame (the keyboard).
    private var backToEndMayFlip: Bool {
        switch scrollTrack.phase {
        case .interacting, .tracking, .idle: return true
        case .decelerating, .animating: return false
        @unknown default: return false
        }
    }

    /// Focusing the composer is a wish to be at the end, not an order (H2 §2, iMessage): within a
    /// real screen the transcript glides there and the last line keeps resting on the composer;
    /// further up the reader's place wins and the button offers the way back.
    private func endScrollRequested() {
        guard scrollTrack.distanceFromContentBottom > Self.followSlack else { return }
        let screen = stableViewportHeight > 0 ? stableViewportHeight : scrollTrack.visibleHeight
        guard scrollTrack.distanceFromContentBottom <= screen else {
            if controller.isFollowing { controller.isFollowing = false }
            decideBackToEnd()
            return
        }
        withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    // MARK: Header

    /// The header's auto-hide rule (H2 §3). Per frame this is arithmetic on the track's plain
    /// state machine: SwiftUI hears one `Bool` write when the bar flips. Only user phases
    /// accumulate, so a send glide, a back-to-end or a jump never moves the header.
    private func updateHeaderReveal(
        _ metrics: ScrollFollowMetrics, from previous: ScrollFollowMetrics
    ) {
        let canScroll = metrics.contentHeight > metrics.visibleHeight + 1
        switch scrollTrack.phase {
        case .interacting, .tracking, .decelerating:
            let viewport = stableViewportHeight > 0 ? stableViewportHeight : metrics.visibleHeight
            let changed = scrollTrack.headerReveal.scroll(
                by: metrics.offsetY - previous.offsetY,
                revealDistance: TranscriptHeader.revealDistance(viewport: viewport),
                hideDistance: TranscriptHeader.hideDistance,
                roomAbove: metrics.distanceFromTop,
                roomBelow: metrics.distanceFromBottom,
                canScroll: canScroll)
            if changed { publishHeaderVisibility() }
        case .idle:
            // A conversation that fits the screen keeps its chrome, whatever it last did.
            if !canScroll { revealHeader() }
        default:
            break
        }
    }

    private func publishHeaderVisibility() {
        let hidden = scrollTrack.headerReveal.isHidden
        if controller.headerHidden != hidden { controller.headerHidden = hidden }
    }

    /// Shows the header now: a send, a jump to an older turn, or a conversation that stopped
    /// scrolling. One `Bool` write, only when it actually changes.
    private func revealHeader() {
        guard scrollTrack.headerReveal.reveal() else { return }
        publishHeaderVisibility()
    }

    // MARK: Runway

    /// A turn arrived. If it is the message you just sent, the runway opens; the runway is what
    /// makes `.top` reachable (D1 §2). The tail turn's height may already have been reported
    /// before this ran (H2 §1), so it comes from the track.
    private func beginRunway(for turnId: String?) {
        guard let turnId, controller.anchoringToAnswer,
            let turn = store.turns.last, turn.userMessage != nil
        else { return }
        runway.open(
            turnId: turnId, viewport: scrollTrack.visibleHeight,
            turnHeight: scrollTrack.turnHeight(of: turnId), slack: Self.runwaySlack)
        // The landing position is *under the header*: a send is an explicit return to live
        // content, so the bar is there for it, like a freshly opened conversation (H2 §3).
        revealHeader()
    }

    /// The glide the open owes, granted on the first geometry pass that has both a viewport and a
    /// proxy (the first message of a conversation arrives before its scroll view reports one).
    /// The runway's height is written in this same update, ahead of the proxy's scroll request, so
    /// the scroll resolves against the grown content and needs no main-actor hop.
    private func openRunwayIfPossible(proxy: ScrollViewProxy) {
        guard runway.owesGlide, let turnId = runway.turnId,
            scrollTrack.visibleHeight > 0, controller.anchoringToAnswer
        else { return }
        var next = runway
        next.grant(viewport: scrollTrack.visibleHeight, slack: Self.runwaySlack)
        runway = next
        withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
            proxy.scrollTo(turnId, anchor: .top)
        }
    }

    /// The tail turn's height moved: the runway follows it downhill, and once the answer fills the
    /// screen the anchor hands over to the follow rules.
    private func updateRunway(turnId: String, height: CGFloat) {
        guard runway.turnId == turnId else { return }
        var next = runway
        let filled = next.measure(
            turnHeight: height, viewport: scrollTrack.visibleHeight, slack: Self.runwaySlack)
        if next != runway { runway = next }
        guard filled, controller.anchoringToAnswer else { return }
        controller.anchoringToAnswer = false
        controller.isFollowing = true
    }

    /// The viewport changed (the keyboard, mostly, or rotation): the tail turn keeps its bottom on
    /// the visible line, and the runway may only shrink (H2 §1).
    private func runwayViewportChanged() {
        guard runway.measured, runway.height > 0 else { return }
        var next = runway
        guard next.viewportChanged(viewport: scrollTrack.visibleHeight, slack: Self.runwaySlack)
        else { return }
        runway = next
    }

    /// The runway's close at rest, in two steps (H2 §1). First the part below the visible bottom:
    /// changing off-screen room moves nothing, so this trim can never jump. Then, if what is left
    /// is a conversation that fits the screen, the rest goes too — a short answer's room is visible
    /// but no scroll can reach it, and holding it would keep a blank screen under the last line.
    /// The content settles onto the composer, which is where a short conversation lives.
    private func closeRunwayAtRest() {
        guard runway.height > 0 else { return }
        let contentWithoutRunway = scrollTrack.contentHeight - runway.height
        trimRunwayIfNeeded()
        guard runway.height > 0, !controller.anchoringToAnswer,
            contentWithoutRunway <= scrollTrack.visibleHeight + 1
        else { return }
        var next = runway
        guard next.collapse() else { return }
        withAnimation(Motion.settle.resolved(reduceMotion: reduceMotion)) {
            runway = next
            // Same update as the size change: the tail growth anchor sees the bottom and the
            // short conversation comes to rest on the composer.
            if !controller.isFollowing { controller.isFollowing = true }
        }
    }

    /// Removes the part of the runway that sits below the visible bottom. Changing off-screen
    /// room moves nothing the reader is looking at, so this is the one trim that can never jump:
    /// it is how the send runway loses the room the reader has scrolled past (H2 §1).
    private func trimRunwayIfNeeded() {
        guard runway.height > 0 else { return }
        var next = runway
        guard next.trim(toDistanceFromBottom: max(0, scrollTrack.distanceFromBottom)) else { return }
        runway = next
    }

    /// Where the viewport sat when an older page was requested, so the prepend can be undone.
    private struct HistoryAnchor: Equatable {
        var contentHeight: CGFloat
        var offsetY: CGFloat
        /// The start cursor at request time; unchanged means the page prepended nothing.
        var cursor: TimelineCursor?
        var startedAt: Date
        /// The growth already compensated; a correction is re-applied only when the content
        /// grows further, so the reader can scroll freely right after a page lands.
        var appliedGrowth: CGFloat = 0
    }

    private struct ScrollFollowMetrics: Equatable {
        /// Distance from the end of the content to the bottom of what you can see. 0 at the end.
        /// Includes the inset, so it is what the follow and runway rules compare against the
        /// visible area; the button's decision never uses it (J3 §3).
        var distanceFromBottom: CGFloat
        /// J3 §3: the same distance without the scrolling behaviour's viewport contribution —
        /// the end of the content to the bottom of the content area. It is the *content's* own gap.
        var distanceFromContentBottom: CGFloat
        /// Offset below the top of the content. 0 at the very top.
        var distanceFromTop: CGFloat
        var contentHeight: CGFloat
        var offsetY: CGFloat
        /// The scroll view's own height, chrome and safe areas included.
        var viewportHeight: CGFloat
        /// The space the bars leave for content: the runway's and the follow rules' viewport.
        var visibleHeight: CGFloat
    }

    /// How close to the end counts as "at the end" (D1 §3).
    static let followSlack: CGFloat = 8

    /// Older history loads itself: no "Load earlier" row and no button. While the top of the
    /// transcript is within about one screen of the viewport, the next page is fetched; the
    /// prepend is compensated so the reader's place does not move (UX spec §4.3).
    private func loadOlderIfNeeded(_ metrics: ScrollFollowMetrics) {
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
    private func restoreHistoryAnchor(_ metrics: ScrollFollowMetrics) -> Bool {
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

    /// A step in find: the row's own view id, centred.
    private func scrollToRow(_ seq: Int, animated: Bool, proxy: ScrollViewProxy) {
        if animated {
            withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
                proxy.scrollTo("row:\(seq)", anchor: .center)
            }
        } else {
            proxy.scrollTo("row:\(seq)", anchor: .center)
        }
    }

    /// Find opened mid-conversation: keep the reader where they were (anchoring to the topmost
    /// mounted turn), so the bar appearing does not move the conversation.
    private func restoreFindAnchor() {
        controller.find.anchor = scrollTrack.lastTrackedTurn
    }

    /// Find closed: back to the turn the reader was on, or to the end.
    private func restoreScroll(proxy: ScrollViewProxy) {
        withAnimation(Motion.disclosure.resolved(reduceMotion: reduceMotion)) {
            if let anchor = controller.find.anchor,
                store.turns.contains(where: { $0.id == anchor })
            {
                proxy.scrollTo(anchor, anchor: .top)
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    /// Jumps the transcript to `id` (a turn view id). Reduce Motion jumps without animation.
    ///
    /// Long jumps use DSH's glide-lead (`turn-nav.ts:412-474`): go most of the way instantly, then
    /// glide the last `glideLead` points, so the reader is not left waiting on a whole-distance
    /// animation. Short jumps just glide.
    private func jumpToTurn(_ id: String, proxy: ScrollViewProxy) {
        // Jumping backwards releases the tail-follow, like M7b.
        controller.isFollowing = false
        // A jump back into the conversation is a deliberate move toward reading: the header
        // comes back. Forward jumps never change it (H2 §3).
        if let targetY = scrollTrack.offset(of: id), targetY < scrollTrack.contentOffset {
            revealHeader()
        }
        showLandingLine(for: id)
        guard !reduceMotion else {
            proxy.scrollTo(id, anchor: .top)
            return
        }
        guard let targetY = scrollTrack.offset(of: id) else {
            // A row that has never been laid out has no offset to lead from: jump instantly to
            // measure it, then take the last stretch back and glide (the geometry handler
            // finishes the jump).
            pendingLeadJump = PendingLeadJump(id: id, fromOffset: scrollTrack.contentOffset)
            proxy.scrollTo(id, anchor: .top)
            return
        }
        let distance = targetY - scrollTrack.contentOffset
        guard abs(distance) > Self.glideLead else {
            withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                proxy.scrollTo(id, anchor: .top)
            }
            return
        }
        let leadY = targetY - (distance > 0 ? Self.glideLead : -Self.glideLead)
        pendingGlide = PendingGlide(id: id)
        scrollPosition.scrollTo(y: leadY)
    }

    /// The landed turn's wayfinding line: a 2 pt ink rule over its first row, fading in and out
    /// over `landingDuration` (DSH `turn-nav.css:155-194`).
    private func showLandingLine(for id: String) {
        landingTurnId = id
        landingStartedAt = Date()
        let captured = id
        Task {
            try? await Task.sleep(for: .seconds(Self.landingDuration))
            guard landingTurnId == captured else { return }
            landingTurnId = nil
        }
    }

    /// The timeline position under the top of the viewport: the first row of the topmost turn the
    /// lazy stack has mounted. The track keeps that anchor, so a scroll frame reads it O(1) and
    /// only reports when it actually moved (finding #18).
    private func reportReadingPosition() {
        var seq = scrollTrack.topVisibleSeq
        if seq == nil, controller.isFollowing { seq = controller.lastPromptSeq }
        guard seq != scrollTrack.reportedReadingAnchor else { return }
        scrollTrack.reportedReadingAnchor = seq
        store.promptOutline.reportReadingPosition(anchorSeq: seq)
    }

    /// Scroll-reveals the rail and keeps it up briefly; hidden again shortly after scrolling stops.
    /// One task per reveal cycle: a scroll frame pushes the deadline out instead of cancelling and
    /// restarting a Task every frame (finding #18).
    private func revealTurnRail() {
        guard ChatOutlineRail.promptRailEnabled, controller.outlineAvailable else { return }
        if !turnNavVisible { turnNavVisible = true }
        scrollTrack.turnNavIdleDeadline = Date().addingTimeInterval(Self.turnNavIdleDuration)
        guard scrollTrack.turnNavIdleTask == nil else { return }
        scrollTrack.turnNavIdleTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let deadline = scrollTrack.turnNavIdleDeadline else { break }
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0, !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            scrollTrack.turnNavIdleDeadline = nil
            scrollTrack.turnNavIdleTask = nil
            turnNavVisible = false
        }
    }

    // MARK: Chrome

    /// U5: the prompt rail — every prompt of the conversation as a tick at the trailing edge,
    /// drawn over the transcript with no reserved margin. It appears while scrolling and for a
    /// moment after; its 24 pt touch strip is live while it shows.
    @ViewBuilder private var outlineRail: some View {
        if ChatOutlineRail.promptRailEnabled, case .ready = store.phase,
            controller.outlineAvailable
        {
            ChatOutlineRail(
                items: controller.outlineItems,
                activeSeq: store.promptOutline.activeSeq,
                viewportHeight: transcriptHeight,
                isRevealed: turnNavVisible,
                onJump: { seq in controller.jumpToPrompt(seq) },
                onReveal: { revealTurnRail() })
            .transition(.opacity)
        }
    }
}

/// Scroll bookkeeping for the transcript: which turns the lazy stack has mounted, where they sit
/// in the content, and the rail's idle timer. Nothing observes these values, so they must not be
/// `@State` — a `@State` write invalidates its whole view, and these change every time a turn
/// enters or leaves the viewport while the reader scrolls (P3).
final class TranscriptScrollTrack: @unchecked Sendable {
    /// The named space the transcript's content is measured in, for the jump lead.
    static let contentSpace = "paseo.transcript.content"

    var visibleTurnIds: Set<String> = []
    var lastTrackedTurn: String?
    /// The viewport's content offset, updated once per scroll frame (O(1)).
    var contentOffset: CGFloat = 0
    /// The current scroll phase. A plain field: nothing observes it, so a scroll frame that only
    /// moves the finger never invalidates the body (D1 §3).
    var phase: ScrollPhase = .idle
    /// How far the content's end is below the visible bottom, from the last scroll frame.
    var distanceFromBottom: CGFloat = 0
    /// The end of the content to the bottom of the content area, inset-free (J3 §3). This is the
    /// value the "Back to the end" decision reads; it is unaffected by the keyboard and the
    /// composer's height.
    var distanceFromContentBottom: CGFloat = 0
    /// The content's own height, from the last scroll frame; the runway's close at rest reads it.
    var contentHeight: CGFloat = 0
    /// The space the bars leave for content, from the last scroll frame.
    var visibleHeight: CGFloat = 0
    /// The topmost mounted turn's prompt seq: the reading-position anchor, read O(1) per frame.
    private(set) var topVisibleSeq: Int?
    /// The last anchor reported to `PromptOutline`, so a scroll frame does not re-resolve it.
    var reportedReadingAnchor: Int?
    /// The instant the rail should auto-hide; a scroll frame pushes it out.
    var turnNavIdleDeadline: Date?
    /// The rail's one idle task; a scroll frame extends the deadline instead of restarting it.
    var turnNavIdleTask: Task<Void, Never>?
    /// The header's reveal rule. The signed travel accumulates here, in plain memory, so a scroll
    /// frame never invalidates a body; the controller hears only the flips (H2 §3).
    var headerReveal = HeaderRevealState()

    private var turnSeqs: [String: Int] = [:]
    private var turnOffsets: [String: CGFloat] = [:]
    private var turnHeights: [String: CGFloat] = [:]
    private var topVisibleTurnId: String?

    func turnAppeared(_ id: String, seq: Int?) {
        visibleTurnIds.insert(id)
        lastTrackedTurn = id
        if let seq { turnSeqs[id] = seq }
        if topVisibleTurnId == nil, let seq {
            topVisibleTurnId = id
            topVisibleSeq = seq
        }
    }

    /// The turn's laid-out height. Recorded for every mounted turn: the tail can report before the
    /// runway is opened for it, and the ordering must not decide the runway's first frame (H2 §1).
    func turnHeightChanged(_ id: String, height: CGFloat) {
        turnHeights[id] = height
    }

    /// The last height the turn reported; nil when it has not been laid out yet.
    func turnHeight(of id: String) -> CGFloat? { turnHeights[id] }

    func turnDisappeared(_ id: String) {
        visibleTurnIds.remove(id)
        turnSeqs.removeValue(forKey: id)
        turnOffsets.removeValue(forKey: id)
        turnHeights.removeValue(forKey: id)
        guard topVisibleTurnId == id else { return }
        topVisibleTurnId = nil
        topVisibleSeq = nil
        // The top left with the viewport: the next topmost mounted turn takes over. Only this
        // rare path scans, and it keeps the anchor from reading nil for a whole frame.
        let remaining = visibleTurnIds.compactMap { id in
            turnOffsets[id].map { offset in (offset, id) }
        }
        if let top = remaining.min(by: { $0.0 < $1.0 }) {
            topVisibleTurnId = top.1
            topVisibleSeq = turnSeqs[top.1]
        }
    }

    func turnOffsetChanged(_ id: String, offset: CGFloat) {
        turnOffsets[id] = offset
        guard let seq = turnSeqs[id] else { return }
        guard let topId = topVisibleTurnId else {
            topVisibleTurnId = id
            topVisibleSeq = seq
            return
        }
        guard id != topId, offset < (turnOffsets[topId] ?? .infinity) else { return }
        topVisibleTurnId = id
        topVisibleSeq = seq
    }

    /// The content offset of a mounted turn, for the jump lead. Nil when it was never laid out.
    func offset(of id: String) -> CGFloat? { turnOffsets[id] }
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

/// The second half of a glide-lead: the instant jump has landed, so the last stretch glides.
struct PendingGlide: Equatable {
    var id: String
}

/// A jump to a row that had never been laid out: jump instantly to measure its offset, then take
/// the last stretch back and glide from there.
struct PendingLeadJump: Equatable {
    var id: String
    var fromOffset: CGFloat
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
private struct ResolvedPermissionLines: View {
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

/// The timeline position of a turn's first row, for the outline's reading-position report. A turn
/// without a leading user message (rewinds, streamed tails) starts at its first segment row.
extension Turn {
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
