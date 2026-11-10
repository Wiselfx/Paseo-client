#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The conversation's timeline, and the only view that owns a scroll handle.
///
/// **Reads:** `store.turns`, `store.pendingPermissions`, `store.phase`, `store.backgroundWork`,
/// `store.isLoadingOlder`, `store.promptOutline` (rail + reading position), `controller.find`
/// (open/seq/flash), `controller.isFollowing` / `anchoringToAnswer`, `controller.outlineItems`
/// (rail), `controller.landingTurnId`. It reads `store.timeline` only for the pending-row
/// signature (one dictionary-free pass over the ids while a send is pending).
struct TranscriptView: View {
    @Bindable var store: ConversationStore
    let controller: ChatController

    /// Turn-nav motion constants, ported from DSH's `turn-nav.ts` / `turn-nav.css`.
    static let glideLead: CGFloat = 480
    /// The glide's duration (`easeScrollFor`'s short glide).
    static let glideDuration: TimeInterval = 0.3
    /// The landing line's fade (`turn-nav.css:155-194`).
    static let landingDuration: TimeInterval = 1.4
    /// How long the rail stays up after the last scroll frame.
    static let turnNavIdleDuration: TimeInterval = 1.5
    /// The reading-position report's throttle while scrolling.
    static let readingReportInterval: TimeInterval = 0.1

    @State private var scrollProxy: ScrollViewProxy?
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellDrawer) private var shellDrawer

    var body: some View {
        content
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
        VStack(spacing: 0) {
            if store.turns.isEmpty, store.pendingPermissions.isEmpty {
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
            } else {
                transcript
            }
        }
    }

    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 27) {
                        turns
                        pendingPermissionCards
                        resolvedPermissionLines
                        backgroundWorkRow
                        Color.clear.frame(height: 1).id("bottom")
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
                .overlay(alignment: .bottom) { transcriptFade }
                .overlay(alignment: .bottom) { backToEnd.padding(.bottom, 7) }
                .overlay(alignment: .trailing) { outlineRail }
                .onChange(of: controller.find.isOpen) { _, isOpen in
                    if isOpen { restoreFindAnchor(proxy: proxy) } else { restoreScroll(proxy: proxy) }
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
                    withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                        scrollPosition.scrollTo(edge: .bottom)
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    reportReadingPosition()
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .interacting, .tracking, .decelerating, .animating:
                        revealTurnRail()
                    case .idle:
                        reportReadingPosition()
                    @unknown default:
                        reportReadingPosition()
                    }
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
                    handleScroll(metrics, proxy: proxy)
                }
                .environment(\.claudeProcessCap, min(400, geometry.size.height * 0.5))
            }
        }
    }

    /// While following, tail growth pins to the bottom with no animation; while anchored to a
    /// just-sent message (or reading back), the top stays put (M7d).
    private var followAnchor: UnitPoint {
        controller.isFollowing && !controller.anchoringToAnswer ? .bottom : .top
    }

    // MARK: Rows

    @ViewBuilder private var turns: some View {
        // One read of the tail id, before the loop: a turn never scans the list to know it is last.
        let lastId = store.turns.last?.id
        // Find inputs are computed per row only while find is open; otherwise both are nil and no
        // turn scans its rows.
        let findSeq = controller.find.isOpen ? controller.findSeq : nil
        let flashSeq = controller.find.isOpen ? controller.find.flash : nil
        ForEach(store.turns) { turn in
            TurnRow(
                turn: turn,
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
        }
    }

    @ViewBuilder private var pendingPermissionCards: some View {
        if !store.pendingPermissions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.pendingPermissions) { request in
                    ClaudePermissionCard(request: request, store: store) { answered in
                        controller.permissionResolvedLines.append(answered)
                    }
                }
            }
            .animation(
                Motion.disclosure.resolved(reduceMotion: reduceMotion),
                value: store.pendingPermissions.count)
        }
    }

    @ViewBuilder private var resolvedPermissionLines: some View {
        if !controller.permissionResolvedLines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(controller.permissionResolvedLines) { item in
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

    @ViewBuilder private var backgroundWorkRow: some View {
        if store.backgroundWork.hasRunningItems {
            BackgroundWorkRow(items: store.backgroundWork.items) {
                Haptics.selection()
                controller.sheet = .backgroundWork
            }
        }
    }

    // MARK: Scroll

    private func handleScroll(_ metrics: ScrollFollowMetrics, proxy: ScrollViewProxy) {
        if transcriptHeight != metrics.viewportHeight {
            transcriptHeight = metrics.viewportHeight
        }
        scrollTrack.contentOffset = metrics.offsetY
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
        if controller.anchoringToAnswer {
            // While anchored the message stays pinned to the top; only once the growing content
            // overflows the viewport does tail-follow take over.
            if metrics.distanceFromBottom > 16 {
                controller.anchoringToAnswer = false
                controller.isFollowing = true
            }
            return
        }
        if metrics.distanceFromBottom <= 16 {
            if !controller.isFollowing { controller.isFollowing = true }
        } else if metrics.distanceFromBottom > metrics.viewportHeight / 3 {
            if controller.isFollowing { controller.isFollowing = false }
        }
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
        var distanceFromBottom: CGFloat
        /// Offset below the top of the content. 0 at the very top.
        var distanceFromTop: CGFloat
        var contentHeight: CGFloat
        var offsetY: CGFloat
        var viewportHeight: CGFloat
    }

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
    private func restoreFindAnchor(proxy: ScrollViewProxy) {
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
            withAnimation(Motion.glide.animation) { proxy.scrollTo(id, anchor: .top) }
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
        if seq == nil, controller.isFollowing { seq = controller.outlineItems.last?.seq }
        guard seq != scrollTrack.reportedReadingAnchor else { return }
        scrollTrack.reportedReadingAnchor = seq
        store.promptOutline.reportReadingPosition(anchorSeq: seq)
    }

    /// Scroll-reveals the rail and keeps it up briefly; hidden again shortly after scrolling stops.
    /// One task per reveal cycle: a scroll frame pushes the deadline out instead of cancelling and
    /// restarting a Task every frame (finding #18).
    private func revealTurnRail() {
        guard controller.outlineAvailable else { return }
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

    /// The 40 pt fade band: the transcript melts into the canvas just above the composer.
    private var transcriptFade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.background.opacity(0), location: 0),
                .init(color: Palette.background, location: 1),
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
        if !controller.find.isOpen, !controller.isFollowing {
            Button {
                Haptics.selection()
                controller.anchoringToAnswer = false
                controller.isFollowing = true
                withAnimation(Motion.glide.resolved(reduceMotion: reduceMotion)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.glyph(.regular, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Palette.panel, in: .circle)
                    .overlay {
                        Circle().strokeBorder(Palette.cardBorder, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityIdentifier("transcript.backToEnd")
            .accessibilityLabel("Back to the end")
        }
    }

    /// U5: the prompt rail — every prompt of the conversation as a tick at the trailing edge,
    /// drawn over the transcript with no reserved margin. It appears while scrolling and for a
    /// moment after; its 24 pt touch strip is live while it shows.
    @ViewBuilder private var outlineRail: some View {
        if case .ready = store.phase, controller.outlineAvailable {
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
    /// The topmost mounted turn's prompt seq: the reading-position anchor, read O(1) per frame.
    private(set) var topVisibleSeq: Int?
    /// The last anchor reported to `PromptOutline`, so a scroll frame does not re-resolve it.
    var reportedReadingAnchor: Int?
    /// The instant the rail should auto-hide; a scroll frame pushes it out.
    var turnNavIdleDeadline: Date?
    /// The rail's one idle task; a scroll frame extends the deadline instead of restarting it.
    var turnNavIdleTask: Task<Void, Never>?

    private var turnSeqs: [String: Int] = [:]
    private var turnOffsets: [String: CGFloat] = [:]
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

    func turnDisappeared(_ id: String) {
        visibleTurnIds.remove(id)
        turnSeqs.removeValue(forKey: id)
        turnOffsets.removeValue(forKey: id)
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
