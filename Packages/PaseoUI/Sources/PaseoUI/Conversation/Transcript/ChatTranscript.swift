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
    /// The gap between rows in the transcript's stack, and the runway's arithmetic depends on it.
    static let turnSpacing: CGFloat = 27
    /// What the stack itself keeps under the tail turn: the row gap before the end marker, the
    /// marker itself and the bottom padding. The runway is the empty room you can see, so it must
    /// not count them (D1 §2).
    static let runwaySlack: CGFloat = turnSpacing + 1 + 20
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
    /// Brings a row that may be far away into view in steps that each run on a settled layout: find,
    /// the outline rail, a media item and closing find (`TranscriptJumpRunner`).
    @State private var jumper = TranscriptJumpRunner()
    /// Where the current find match's row is (it reports its own frame while it is the match).
    @State private var findRows = FindRowProbe()
    /// The last throttled reading-position / rail tick, so a scroll frame does O(1) work.
    @State private var lastRailTick = Date.distantPast
    /// True while a finger, a flick or the deceleration owns the transcript. A plain `Bool`
    /// written at phase boundaries only: the phase itself lives in `TranscriptScrollTrack`, so a
    /// scroll frame never invalidates the body.
    @State private var scrollHeld = false
    /// True from open until the transcript first rests at the end or the reader takes it over. While
    /// true, a frame that is not at the end re-seats the real bottom (see `repinOpen`).
    @State private var openPin = true
    /// The last offset the open re-seat acted on, so one geometry never asks twice.
    @State private var openPinKey: CGFloat = -1
    /// A ceiling, so a layout that never converges cannot loop.
    @State private var openPinCount = 0
    @State private var openNudgedHeight: CGFloat = -1
    /// The oldest turn mounted (W1). Opening a long conversation used to hand the lazy stack every
    /// turn: it estimated the content, landed on an estimated bottom, built about a hundred markdown
    /// pieces in one pass (1.4 to 2.3 s) and then re-built them as the estimate corrected. Only the
    /// newest `windowSize` turns are in the stack; scrolling toward the top reveals `windowStep` more
    /// (the same anchor that undoes a prepended history page keeps the reader's line), and a jump or a
    /// find match in an older turn reveals it first. Nil until the first turns arrive.
    ///
    /// Held as a position in the timeline (the first row's seq of the oldest mounted turn), never as a turn
    /// id: a turn's id is its first row's id, so an older page prepending rows to a partial turn at the edge
    /// of a loaded window changes it, and a window keyed by the old id silently fell back to the newest 16
    /// turns while a find or jump was on its way to an older one.
    @State private var windowStartSeq: Int?
    static let windowSize = 16
    static let windowStep = 12
    /// Turns mounted above a find or jump target when the window grows to reach it, so the reader can
    /// look up from the match without the window growing again at once.
    static let windowLead = 8
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
        let _ = PaseoPerf.body("Transcript")
        let _ = PaseoPerf.why(Self.self)
        content
            // A turn arrived. If you just sent it, the runway opens and it glides to the top.
            .onChange(of: store.turns.last?.id) { old, id in
                // A turn arriving after the open is live traffic, not the open: stop re-seating.
                if old != nil { openPin = false }
                beginRunway(for: id)
            }
            .onChange(of: store.isRunning) { _, _ in openPin = false }
            // The first render of the newest turns finds their pieces, documents and highlights ready
            // when this has run ahead of it (`ProseWarmup`, off the main actor, newest first).
            .task(id: store.turns.isEmpty) {
                guard !store.turns.isEmpty else { return }
                ProseWarmup.startForOpen(store: store, limit: Self.windowSize)
            }
            // Blank guard (W1): a long chat can open with the lazy stack holding no rows under its final
            // offset until the visible rect changes (reproduced on plain launches; the open nudge covers most
            // cases, not all). If turns exist, the viewport has a height and nothing has mounted after a
            // moment, move the offset by two points (invisible) and look again.
            .task(id: store.turns.isEmpty) {
                guard !store.turns.isEmpty else { return }
                for (attempt, delay) in [0.8, 1.0, 1.5, 2.5].enumerated() {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, !scrollHeld else { return }
                    guard !scrollTrack.hasTurnInViewport, scrollTrack.visibleHeight > 0 else { return }
                    PaseoPerf.count("blank.nudge")
                    if attempt % 2 == 0 {
                        scrollPosition.scrollTo(y: max(scrollTrack.contentOffset - 2, 0))
                    } else {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                }
            }
            // The open is over: the first quiet moment of this conversation. The shared web view starts
            // here (a second later, so the last layout pass is done), not inside the open (W1).
            .onChange(of: openPin) { _, pinned in
                guard !pinned else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !scrollHeld else { return }
                    RichWebSnapshotRenderer.shared.prewarm()
                }
            }
            // The keyboard is the reader acting (rule 14). Its first frame moves the insets, which the open
            // re-seat took for an unfinished layout and answered with a `scrollTo(edge: .bottom)` inside
            // that frame (W1): end the open when the keyboard announces itself, before the insets move.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                openPin = false
            }
            // Fix the window's head as soon as there is something to window, so a turn appended at
            // the tail never slides it.
            .onChange(of: store.turns.isEmpty) { _, empty in
                if !empty, windowStartSeq == nil, let first = windowedTurns.first {
                    windowStartSeq = first.firstRowSeq
                }
            }
            .onAppear {
                if windowStartSeq == nil, let first = windowedTurns.first {
                    windowStartSeq = first.firstRowSeq
                }
            }
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

    /// Both the states and the transcript stay mounted, so the bottom bar attached to this view is
    /// never rebuilt by a swap (N6 A). The state view draws on top while there is nothing to show.
    @ViewBuilder private var content: some View {
        ZStack {
            transcript
                .accessibilityHidden(showsStates)
            if showsStates {
                states
            }
        }
    }

    /// Loading, empty or failed: nothing in the transcript to show. O(1), two emptiness checks.
    private var showsStates: Bool {
        store.turns.isEmpty && store.pendingPermissions.isEmpty
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
            // The prose column: the scroll view's width less the 16 pt margins. Measured here,
            // once per screen, and published to every media card (V1.2). The lazy stack is
            // pinned to it too, so no row can widen the transcript's content: a card that
            // reported a width wider than the column used to re-wrap every row above it, and
            // a lazy row that re-wraps keeps its old height (V1.3).
            let column = max(geometry.size.width - 32, 0)
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
                    .frame(width: column > 1 ? column : nil, alignment: .leading)
                    .clipped()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .coordinateSpace(name: TranscriptScrollTrack.contentSpace)
                }
                .environment(\.richProseWidth, column)
                .environment(\.findRowProbe, findRows)
                .coordinateSpace(name: TranscriptScrollTrack.viewportSpace)
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
                    if isOpen {
                        openPin = false
                        restoreFindAnchor()
                    } else {
                        jumper.cancel()
                        restoreScroll()
                    }
                }
                .onChange(of: controller.find.jump) { _, jump in
                    guard let jump else { return }
                    controller.find.jump = nil
                    scrollToMatch(jump)
                }
                .onChange(of: controller.pendingJump) { _, jump in
                    guard let jump else { return }
                    controller.pendingJump = nil
                    jumpToTurn(jump.id)
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
                }
                .onScrollGeometryChange(for: ScrollFollowMetrics.self) { geometry in
                    ScrollFollowMetrics(
                        // `contentInsets.bottom` is the composer: measured from the end of the
                        // content you can actually see, so 0 is the end and negative is past it.
                        distanceFromBottom: geometry.contentSize.height - geometry.contentOffset.y
                            - geometry.bounds.height + geometry.contentInsets.bottom,
                        // J3 §3: the end of the content to the scroll view's own bottom edge, with
                        // no inset term. The keyboard and a growing composer only change
                        // `contentInsets.bottom`, so this does not move when they come and go
                        // (lead fix: the first cut kept `+ contentInsets.bottom`, i.e. the old
                        // distance). At the end it is minus the bar's inset, which reads as the end.
                        distanceFromContentBottom: geometry.contentSize.height
                            - geometry.contentOffset.y - geometry.bounds.height,
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

    /// The turns the stack holds: from the window's first turn to the newest.
    private var windowedTurns: ArraySlice<Turn> {
        store.turns[windowStartIndex...]
    }

    /// Turns older than the window, still in the store.
    private var hiddenTurnCount: Int { windowStartIndex }

    /// The index of the window's first turn in `store.turns`: the first turn that ends at or after the
    /// window's start position, else the newest `windowSize` turns.
    private var windowStartIndex: Int {
        let all = store.turns
        if let start = windowStartSeq,
            let index = FindNavigation.firstTurnIndex(endingAtOrAfter: start, in: all)
        {
            return index
        }
        return max(all.count - Self.windowSize, 0)
    }

    /// Moves the window start back by `count` turns.
    private func growWindow(by count: Int) -> Bool {
        let all = store.turns
        let current = windowStartIndex
        let target = max(current - count, 0)
        guard target < current, all.indices.contains(target),
            let seq = all[target].firstRowSeq
        else { return false }
        windowStartSeq = seq
        return true
    }

    /// Mounts the turn at `index` with `windowLead` turns above it when it is older than the window
    /// (find and the rail's jumps reach turns the window holds back). The window stays a suffix of the
    /// conversation, so the tail, the runway and the end marker are untouched; only a target older
    /// than the window grows it, and only to reach the target, never to the whole conversation.
    private func mountTurn(at index: Int) {
        let all = store.turns
        let current = windowStartIndex
        let start = FindNavigation.windowStart(
            forTurnAt: index, currentStart: current, lead: Self.windowLead)
        guard start < current, all.indices.contains(start), let seq = all[start].firstRowSeq
        else { return }
        windowStartSeq = seq
    }

    @ViewBuilder private var turns: some View {
        // One read of the tail id, before the loop: a turn never scans the list to know it is last.
        let lastId = store.turns.last?.id
        // Find inputs are computed per row only while find is open; otherwise both are nil and no
        // turn scans its rows.
        let findSeq = controller.find.isOpen ? controller.find.rowSeq : nil
        let flashSeq = controller.find.isOpen ? controller.find.flash : nil
        // One read of the turn-action value for every row: it changes when the agent or host
        // capabilities change, not per turn, and `TurnRow` compares it (E3 §2).
        let availability = controller.actions.availability
        ForEach(windowedTurns) { turn in
            TurnRow(
                turn: turn,
                availability: availability,
                isLatest: turn.id == lastId,
                findSeq: findSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                flashSeq: flashSeq.flatMap { turn.containsRow(seqEnd: $0) ? $0 : nil },
                isLanding: turn.id == landingTurnId,
                actions: controller.actions,
                isCanceled: turn.turnId.map { store.canceledTurnIds.contains($0) } ?? false
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
        scrollTrack.viewportHeight = metrics.viewportHeight
        scrollTrack.distanceFromBottom = metrics.distanceFromBottom
        scrollTrack.distanceFromContentBottom = metrics.distanceFromContentBottom
        scrollTrack.contentHeight = metrics.contentHeight
        if scrollTrack.visibleHeight != metrics.visibleHeight {
            scrollTrack.visibleHeight = metrics.visibleHeight
            runwayViewportChanged()
        }
        openRunwayIfPossible(proxy: proxy)
        repinOpen(metrics)
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
        if !revealOlderTurnsIfNeeded(metrics) { loadOlderIfNeeded(metrics) }
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

    /// Opening a long conversation at its end (W1). `defaultScrollAnchor(.bottom, for: .initialOffset)`
    /// lands on the offset of an *estimated* bottom: the lazy stack has not measured the rows above it.
    /// As rows realise the content height changes and the offset is left where it was, so a long chat
    /// opened in the middle of itself (a normal launch, 17 000 pt of content) or on rows that were
    /// never built (blank, seen under the perf instrument's timing). The edge scroll targets the *real*
    /// content bottom, so repeating it while the transcript is still opening converges: it stops at
    /// the moment a finger or flick owns the scroll, a send takes over, or after 16 re-seats. (The first rest
    /// cannot end it: that rest is at the estimated end, before the rows below it exist.)
    private func repinOpen(_ metrics: ScrollFollowMetrics) {
        guard openPin else { return }
        if scrollHeld || !controller.isFollowing || controller.anchoringToAnswer || openPinCount >= 16 {
            if PaseoPerf.enabled {
                PaseoPerf.countNamed("openpin.off.held\(scrollHeld).follow\(controller.isFollowing).anchor\(controller.anchoringToAnswer).n\(openPinCount)")
            }
            openPin = false
            return
        }
        guard metrics.contentHeight > metrics.visibleHeight else { return }
        if metrics.distanceFromBottom <= Self.followSlack {
            PaseoPerf.count("openpin.atEnd")
            // A jump of thousands of points leaves the stack without rows under the final offset until
            // the scroll view's visible rect changes; a programmatic scroll to where it already is
            // changes nothing. Two points up is invisible and does change it, once per content height.
            if openNudgedHeight != metrics.contentHeight {
                openNudgedHeight = metrics.contentHeight
                PaseoPerf.count("openpin.nudge")
                scrollPosition.scrollTo(y: max(metrics.offsetY - 2, 0))
            } else {
                // Nudged at this height and still at the end on a later pass: the open is done.
                openPin = false
            }
            return
        }
        let key = metrics.contentHeight * 1000 + metrics.offsetY
        guard key != openPinKey else { return }
        openPinKey = key
        openPinCount += 1
        if PaseoPerf.enabled { PaseoPerf.countNamed("openpin.fire.h\(Int(metrics.contentHeight)).d\(Int(metrics.distanceFromBottom))") }
        scrollPosition.scrollTo(id: "bottom", anchor: .bottom)
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
        // Focusing the composer is the reader acting: the open is over (W1). Ending the re-seat on
        // "only the insets moved" instead left a long chat blank with a tall saved draft.
        openPin = false
        guard scrollTrack.distanceFromBottom > Self.followSlack else { return }
        let screen = stableViewportHeight > 0 ? stableViewportHeight : scrollTrack.visibleHeight
        guard scrollTrack.distanceFromBottom <= screen else {
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
        /// An in-memory window reveal, not a fetched page: nothing is in flight, so the anchor waits
        /// for the growth to land (the 2 s ceiling still ends it).
        var isWindow = false
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
    /// How far from the end a jump to the end marker may rest and still have arrived.
    static let endMargin: CGFloat = 48

    /// Older history loads itself: no "Load earlier" row and no button. While the top of the
    /// transcript is within about one screen of the viewport, the next page is fetched; the
    /// prepend is compensated so the reader's place does not move (UX spec §4.3).
    /// Near the top with older turns held back: reveal the next slice, keeping the reader's line.
    private func revealOlderTurnsIfNeeded(_ metrics: ScrollFollowMetrics) -> Bool {
        // Not while the open re-seat is still settling (W1): its scrolls pass near the top of an estimated
        // content height, and each pass revealed twelve more turns. Sampled opens of a 65 000 pt chat
        // ended with 370 markdown bodies and a 2.6 s stall because the window grew to the whole chat.
        guard !openPin, historyAnchor == nil, hiddenTurnCount > 0,
            metrics.distanceFromTop <= metrics.viewportHeight * 1.5
        else { return false }
        historyAnchor = HistoryAnchor(
            contentHeight: metrics.contentHeight, offsetY: metrics.offsetY,
            cursor: store.timeline.startCursor, startedAt: Date(), isWindow: true)
        if growWindow(by: Self.windowStep) { return true }
        historyAnchor = nil
        return false
    }

    private func loadOlderIfNeeded(_ metrics: ScrollFollowMetrics) {
        guard hiddenTurnCount == 0 else { return }
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
        if !historyLoadInFlight, !anchor.isWindow { historyAnchor = nil }
        return false
    }

    // MARK: Find and jumps

    /// A step in find: resolve the located message to its row against the turns held, fetch its window
    /// when it is not held (upstream `load(epoch, seq)`), mount its turn, and bring the row to the
    /// centre. Upstream `chat-find/model.ts` `navigate` and `viewport.web.ts` `reveal`.
    private func scrollToMatch(_ jump: FindJump) {
        // Stepping through matches is reading, not following the tail; the open re-seat is over too.
        openPin = false
        controller.isFollowing = false
        controller.anchoringToAnswer = false
        guard let target = FindNavigation.target(in: store.turns, seq: jump.seq, role: jump.role) else {
            Task {
                // One window fetch, then once more; a message that still is not there is skipped.
                guard await store.loadTimelineWindow(aroundSeq: jump.seq),
                    FindNavigation.target(in: store.turns, seq: jump.seq, role: jump.role) != nil
                else {
                    controller.find.rowSeq = nil
                    return
                }
                scrollToMatch(jump)
            }
            return
        }
        controller.find.rowSeq = target.rowSeqEnd
        controller.find.moved = true
        findRows.reset()
        mountTurn(at: target.turnIndex)
        let seq = jump.seq
        let role = jump.role
        // Where the match sits in a message taller than the screen: the message rests so the match,
        // not its middle, is in view (upstream scrolls to the match's own rect, `viewport.web.ts`).
        let fraction = FindNavigation.text(of: target, in: store.turns).flatMap { text in
            text.count > FindNavigation.longMessage
                ? FindNavigation.occurrenceFraction(of: store.search.query, in: text, last: jump.backward)
                : nil
        }
        jumper.run(
            .init(
                turnId: { [store] in
                    FindNavigation.target(in: store.turns, seq: seq, role: role)
                        .map { store.turns[$0.turnIndex].id }
                },
                rowId: { [store] in
                    // The row can have streamed on since: resolve it again for its current id.
                    FindNavigation.target(in: store.turns, seq: seq, role: role)
                        .map { "row:\($0.rowSeqEnd)" }
                },
                rowAnchor: { fraction.map { UnitPoint(x: 0.5, y: $0) } ?? .center },
                // Arrived when the match's own point of the row is under the viewport (the row reports
                // its frame while it is the current match). A row that has not reported has not arrived.
                isReached: { [findRows, scrollTrack] in
                    // The match's own point of the row, in the viewport's space (where it is on screen
                    // now): between the top of the viewport and its bottom edge, which is under the composer.
                    guard let frame = findRows.frame(of: target.rowSeqEnd) else { return false }
                    let y = frame.minY + frame.height * (fraction ?? 0.5)
                    return y > 0 && y < scrollTrack.viewportHeight
                },
                verifies: true),
            hooks: jumpHooks(onLanded: { [controller] in
                controller.flash(target.rowSeqEnd)
            }))
    }

    /// The transcript's side of a jump: the scroll position, the stack's mounted turns and the screen.
    private func jumpHooks(onLanded: @escaping @MainActor () -> Void) -> TranscriptJumpRunner.Hooks {
        .init(
            isMounted: { [scrollTrack] id in scrollTrack.visibleTurnIds.contains(id) },
            hop: { [scrollTrack, store] id in
                let all = store.turns
                guard let target = all.firstIndex(where: { $0.id == id }) else { return nil }
                let built = all.indices.filter { scrollTrack.visibleTurnIds.contains(all[$0].id) }
                return FindNavigation.hopTarget(targetIndex: target, builtIndices: built)
                    .map { all[$0].id }
            },
            probe: { [scrollTrack] id in
                guard scrollTrack.visibleHeight > 0 else { return nil }
                // A built turn whose geometry callback has not reported (or was dropped with a re-built
                // view) counts as under the viewport: the aim at its row is what tells, and the layout key
                // still has to hold still.
                let offset = scrollTrack.offset(of: id) ?? scrollTrack.contentOffset
                return .init(
                    turnOffset: offset, turnHeight: scrollTrack.turnHeight(of: id) ?? 1,
                    contentOffset: scrollTrack.contentOffset, visibleHeight: scrollTrack.visibleHeight,
                    contentHeight: scrollTrack.contentHeight)
            },
            scrollTo: { id, anchor, animated in
                if animated {
                    withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                        scrollPosition.scrollTo(id: id, anchor: anchor)
                    }
                } else {
                    scrollPosition.scrollTo(id: id, anchor: anchor)
                }
            },
            // A programmatic scroll leaves the phase at `.animating` even when it has nothing to move (the
            // jump runner waited on `.idle` for eight seconds), so only the reader's own motion counts; the
            // runner sees a programmatic scroll end by the layout holding still.
            isScrolling: { [scrollTrack] in
                switch scrollTrack.phase {
                case .interacting, .tracking, .decelerating: return true
                default: return false
                }
            },
            nudge: { [scrollTrack] in
                PaseoPerf.count("jump.nudge")
                scrollPosition.scrollTo(y: max(scrollTrack.contentOffset - 2, 0))
            },
            landed: onLanded)
    }

    /// Find opened mid-conversation: remember where the reader was (the turn they were on, or the end
    /// when they were following the tail), so closing find after the matches moved them can bring them
    /// back, and the bar appearing does not move the conversation.
    private func restoreFindAnchor() {
        // At the end within the content's own gap (no composer or keyboard inset in it, J3 §3): the
        // inset-including distance is the composer's height at rest, never within the follow slack.
        let atEnd = controller.isFollowing || scrollTrack.distanceFromContentBottom <= Self.endMargin
        controller.find.anchorSeq =
            atEnd
            ? nil
            : scrollTrack.turnAtViewportTop().flatMap { id in
                store.turns.first { $0.id == id }?.firstRowSeq
            }
        controller.find.moved = false
    }

    /// Find closed: if stepping through matches moved the reader, back to the turn they were on, or to
    /// the end. A find that never scrolled leaves the reader where they are.
    private func restoreScroll() {
        guard controller.find.moved else { return }
        controller.find.moved = false
        let all = store.turns
        guard !all.isEmpty else { return }
        if let seq = controller.find.anchorSeq,
            let index = FindNavigation.firstTurnIndex(endingAtOrAfter: seq, in: all)
        {
            mountTurn(at: index)
            jumper.run(
                .init(
                    turnId: { [store] in
                        FindNavigation.firstTurnIndex(endingAtOrAfter: seq, in: store.turns)
                            .map { store.turns[$0].id }
                    },
                    rowId: { nil }, rowAnchor: { .top }),
                hooks: jumpHooks(onLanded: {}))
        } else {
            // The end marker is the real last row (the open re-seat lands on it the same way).
            jumper.run(
                .init(
                    turnId: { "bottom" }, rowId: { "bottom" }, rowAnchor: { .bottom },
                    // The content's own gap to the viewport's bottom, with no inset in it (J3 §3), so the
                    // keyboard going down while the jump runs cannot move the answer. The marker rests at
                    // the bottom edge with the stack's 20 pt padding under it: at the end within a margin.
                    isReached: { [scrollTrack] in
                        scrollTrack.distanceFromContentBottom <= Self.endMargin
                    },
                    approaches: false, verifies: true, glides: false),
                hooks: jumpHooks(onLanded: { [controller] in controller.isFollowing = true }))
        }
    }

    /// Jumps the transcript to a prompt or media row: `id` is `row:<seqEnd>` (or a turn id). The turn is
    /// mounted first when the window holds it back, then `TranscriptJumpRunner` goes to it in steps
    /// (a turn's rows are only known to the stack once the turn is built). Reduce Motion jumps without
    /// the glide (`Motion.resolved`).
    private func jumpToTurn(_ id: String) {
        openPin = false
        // Jumping backwards releases the tail-follow, like M7b.
        controller.isFollowing = false
        controller.anchoringToAnswer = false
        let all = store.turns
        // The row's position in the timeline, or the turn's first row for a turn id: ids move when an
        // older page prepends rows to a partial turn, positions do not.
        let seq: Int?
        let rowId: String?
        if id.hasPrefix("row:"), let rowSeq = Int(id.dropFirst(4)) {
            seq = rowSeq
            rowId = id
        } else {
            seq = all.first { $0.id == id }?.firstRowSeq
            rowId = nil
        }
        let indexOfTurn: @MainActor ([Turn]) -> Int? = { turns in
            guard let seq else { return nil }
            return turns.firstIndex(where: { $0.containsRow(seqEnd: seq) })
                ?? turns.lastIndex(where: { ($0.firstRowSeq ?? Int.max) <= seq })
        }
        guard let index = indexOfTurn(all) else {
            PaseoPerf.mark("jump.noTurn")
            return
        }
        mountTurn(at: index)
        let turnId = all[index].id
        // A jump back into the conversation is a deliberate move toward reading: the header
        // comes back. Forward jumps never change it (H2 §3).
        if let targetY = scrollTrack.offset(of: turnId), targetY < scrollTrack.contentOffset {
            revealHeader()
        } else if !scrollTrack.visibleTurnIds.contains(turnId) {
            revealHeader()
        }
        showLandingLine(for: turnId)
        jumper.run(
            .init(
                turnId: { [store] in indexOfTurn(store.turns).map { store.turns[$0].id } },
                rowId: { rowId }, rowAnchor: { .top }),
            hooks: jumpHooks(onLanded: {}))
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
    /// The scroll view's own frame (it does not scroll): a row's frame in it is where the row is on
    /// screen right now, whatever the stack's estimates above it did since the row last laid out.
    static let viewportSpace = "paseo.transcript.viewport"

    var visibleTurnIds: Set<String> = []
    var lastTrackedTurn: String?
    /// The scroll view's own height (bounds), from the last scroll frame.
    var viewportHeight: CGFloat = 0
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

    /// True when some mounted turn overlaps the viewport (content offsets from the geometry callbacks).
    /// A lazy stack can hold rows that are mounted but nowhere near the offset it landed on: blank.
    var hasTurnInViewport: Bool {
        let top = contentOffset
        let bottom = contentOffset + visibleHeight
        for id in visibleTurnIds {
            guard let offset = turnOffsets[id] else { return true }
            let height = turnHeights[id] ?? 1
            if offset < bottom && offset + height > top { return true }
        }
        return false
    }

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

    /// The mounted turn under the top of the viewport (the one whose bottom is the first below the
    /// offset). O(mounted turns), asked once when find opens; nil when nothing is measured yet.
    func turnAtViewportTop() -> String? {
        var best: (bottom: CGFloat, id: String)?
        for id in visibleTurnIds {
            guard let offset = turnOffsets[id], let height = turnHeights[id] else { continue }
            let bottom = offset + height
            guard bottom > contentOffset + 1 else { continue }
            if let current = best, current.bottom <= bottom { continue }
            best = (bottom, id)
        }
        return best?.id
    }

    /// The content offset of a mounted turn. Nil when it was never laid out.
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

#endif
