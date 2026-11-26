#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var transcriptRowFrames: TranscriptRowFrames?
}
extension View {
    /// The scroll and find anchor of one timeline row: find, the outline and media jumps land on it.
    func rowAnchor(_ seqEnd: Int) -> some View {
        modifier(TranscriptRowAnchor(seqs: [seqEnd]))
    }

    /// One view that stands for several timeline rows (a merged file call).
    func rowAnchors(_ seqEnds: [Int]) -> some View {
        modifier(TranscriptRowAnchor(seqs: seqEnds))
    }
}
// MARK: - Engine

/// The transcript: a `UICollectionView` of SwiftUI cells, and every scroll rule the chat has.
///
/// The lazy stack this replaces estimated the heights of rows it had not built and landed on those
/// estimates; most of the old transcript was machinery to undo that (a re-seat loop on open, a blank
/// guard, a window of mounted turns, a jump runner that aimed again until it arrived, an anchor that
/// scrolled back after a prepend and stopped the reader's flick). Here the layout knows every frame,
/// offsets are set exactly, and growth above the reader is compensated inside the layout pass.
@MainActor
final class TranscriptEngine: NSObject {
    static let followSlack: CGFloat = 8
    static let endMargin: CGFloat = 48
    /// Screens from the top at which older history is fetched.
    static let prefetchScreens: CGFloat = 4
    static let readingReportInterval: TimeInterval = 0.1

    private(set) var store: ConversationStore?
    private(set) var controller: ChatController?
    let history = HistoryStartController(initiallyVisible: true)
    let ui = TranscriptUIState()
    let rowFrames = TranscriptRowFrames()
    let layout = TranscriptLayout()

    private(set) var items: [TranscriptItemID] = []
    private(set) var entries: [TranscriptEntry] = []
    private var indexByID: [TranscriptItemID: Int] = [:]
    private var environment: TranscriptCellEnvironment?
    private var registeredReuse: Set<String> = []

    /// Turn cells kept with their SwiftUI state (an opened work group, a decoded image, highlighted
    /// code). Each turn borrows a slot, a reuse pool of its own, and keeps it while it is among the
    /// most recently shown, so scrolling away and back finds the same cell. Past `cellSlots` the turn
    /// shown least recently (and not on screen) gives its slot up; its cell is rebuilt for the new
    /// turn with fresh state (the root is identified by turn). Memory stays bounded in a long chat.
    static let cellSlots = 64
    private var slotOf: [TranscriptItemID: Int] = [:]
    private var slotOwner: [TranscriptItemID?] = []
    private var slotUse: [Int] = []
    private var useClock = 0
    private var lastEpoch: String?

    private var didInitialLayout = false
    private var insetsApplied = false
    private var lastContentHeight: CGFloat = -1
    private var lastBoundsHeight: CGFloat = -1
    private var lastOffsetY: CGFloat = 0
    private var lastDistanceFromContentBottom: CGFloat = .nan
    private var lastTick = Date.distantPast
    private var reportedReadingAnchor: Int??

    /// A finger, a flick or its deceleration owns the scroll. Read live from the scroll view: a tap
    /// that stops a flick ends the deceleration without any callback.
    var isUserScrolling: Bool { collectionView.isDragging || collectionView.isDecelerating }
    /// A programmatic animated scroll is running (`setContentOffset(_:animated: true)`).
    private var isAnimatingScroll = false
    private var animationCompletion: (@MainActor () -> Void)?
    private var animationToken = 0
    /// Bumped by every new reveal and by a finger: a stale reveal step does nothing.
    private var revealToken = 0
    /// A tap opens and closes things in the cells: until then, a row that a resize moves glides
    /// (`animateMoves`) and the end pin follows in the same curve.
    private var resizeAnimationUntil = Date.distantPast
    /// The item the last tap landed on: only its resize is a disclosure growing where the reader looks
    /// and so is left uncompensated (`compensatesResize`). Other cells keep compensating.
    private var tappedItemID: TranscriptItemID?
    /// The anchor cell of the layout pass in progress (`anchorIndex`); cleared when the pass ends.
    private var anchorLock: TranscriptItemID?
    /// A turn that just finished and is folding its work away above its answer, and until when its
    /// resize keeps the turn's end in place (see `compensatesResize`).
    private var settlingTurn: (id: TranscriptItemID, until: Date)?
    private var isApplyingStructuralChange = false
    private var findFetchTask: Task<Void, Never>?

    private var headerReveal = HeaderRevealState()
    private var turnNavDeadline: Date?
    private var turnNavTask: Task<Void, Never>?

    private var historyLoadInFlight = false
    private var historyTicker: Task<Void, Never>?

    private var heightMemory = TurnHeightMemory()
    private var lastHeightSave = Date.distantPast
    private var estimateCache: [String: CGFloat] = [:]

    private var keyboardAnimation: (duration: Double, curve: Int, until: Date)?
    private var didPrewarmWeb = false

    lazy var container: TranscriptContainerView = makeContainer()
    var collectionView: TranscriptCollectionView { container.collectionView }

    // MARK: Setup

    func attach(store: ConversationStore, controller: ChatController) {
        guard self.store == nil else { return }
        self.store = store
        self.controller = controller
        heightMemory.merge(TurnHeightStore.load())
    }

    private func makeContainer() -> TranscriptContainerView {
        layout.engine = self
        let container = TranscriptContainerView(layout: layout)
        let collectionView = container.collectionView
        collectionView.engine = self
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsSelection = false
        collectionView.selfSizingInvalidation = .enabled
        collectionView.isPrefetchingEnabled = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        // The composer's blur is `ComposerUnderBlur`, drawn by the chat screen: no system edge.
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(transcriptTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        return container
    }

    private var cachedOpenURL: OpenURLAction?

    /// The screen's link handling for cells (file links open the viewer, the rest go to the host's
    /// handler), built once.
    func openURL(for controller: ChatController) -> OpenURLAction {
        if let cachedOpenURL { return cachedOpenURL }
        let host = OpenURLAction { [weak controller] url in
            guard let open = controller?.openURLFromEnvironment else { return .systemAction }
            open(url)
            return .handled
        }
        let action = controller.fileLinkAction(host: host)
        cachedOpenURL = action
        return action
    }

    @objc private func transcriptTapped(_ tap: UITapGestureRecognizer) {
        resizeAnimationUntil = Date.now.addingTimeInterval(0.6)
        let cv = collectionView
        if let indexPath = cv.indexPathForItem(at: tap.location(in: cv)),
            items.indices.contains(indexPath.item)
        {
            tappedItemID = items[indexPath.item]
        } else {
            tappedItemID = nil
        }
        controller?.dismissKeyboard()
    }

    /// A tap just happened and nothing else is moving the content.
    var animatesResizes: Bool {
        Date.now < resizeAnimationUntil && !reduceMotion && !isUserScrolling && !isAnimatingScroll
            && !isApplyingStructuralChange
    }

    /// Rows whose place in the content a resize changed slide there from the old place. A row UIKit
    /// already animates, or one that just appeared, is left alone.
    func animateMoves(of cells: [UICollectionViewCell], from before: [ObjectIdentifier: CGFloat]) {
        var moves: [(cell: UICollectionViewCell, frame: CGRect)] = []
        UIView.performWithoutAnimation {
            for cell in cells {
                guard let oldY = before[ObjectIdentifier(cell)] else { continue }
                let frame = cell.frame
                guard abs(frame.minY - oldY) > 0.5, cell.layer.animationKeys()?.isEmpty ?? true else {
                    continue
                }
                cell.frame = CGRect(x: frame.minX, y: oldY, width: frame.width, height: frame.height)
                moves.append((cell, frame))
            }
        }
        guard !moves.isEmpty else { return }
        UIView.animate(Motion.disclosure.animation, changes: {
            for move in moves { move.cell.frame = move.frame }
        })
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7
        keyboardAnimation = (duration, curve, Date.now.addingTimeInterval(max(duration, 0.05) + 0.1))
    }

    // MARK: Geometry

    private var reduceMotion: Bool { controller?.reduceMotion ?? false }

    private var isFollowing: Bool { controller?.isFollowing ?? true }

    /// The height the bars leave for content.
    var visibleHeight: CGFloat {
        let cv = collectionView
        return max(cv.bounds.height - cv.contentInset.top - cv.contentInset.bottom, 0)
    }

    var minOffsetY: CGFloat { -collectionView.contentInset.top }

    var maxOffsetY: CGFloat {
        let cv = collectionView
        return max(minOffsetY, cv.contentSize.height + cv.contentInset.bottom - cv.bounds.height)
    }

    private func clamp(_ y: CGFloat) -> CGFloat { min(max(y, minOffsetY), maxOffsetY) }

    struct Metrics {
        /// Content offset below the top of the content: 0 at the top.
        var offsetY: CGFloat
        var contentHeight: CGFloat
        /// The area the bars leave for content.
        var viewportHeight: CGFloat
        /// How far the end of the content is below the visible bottom. 0 at the end.
        var distanceFromBottom: CGFloat
        /// The end of the content to the scroll view's own bottom edge, with no inset in it: the keyboard
        /// and the composer do not move it (J3 §3).
        var distanceFromContentBottom: CGFloat
        var canScroll: Bool { contentHeight > viewportHeight + 1 }
    }

    var metrics: Metrics {
        let cv = collectionView
        let offset = cv.contentOffset.y
        return Metrics(
            offsetY: offset + cv.contentInset.top,
            contentHeight: cv.contentSize.height,
            viewportHeight: visibleHeight,
            distanceFromBottom: max(maxOffsetY - offset, 0),
            distanceFromContentBottom: cv.contentSize.height - offset - cv.bounds.height)
    }

    /// The keyboard-independent screen height, for "a screen from the end".
    private var stableScreen: CGFloat {
        let viewport = environment?.viewport ?? 0
        return viewport > 0 ? viewport : visibleHeight
    }

    /// Pin the end after layout: the reader follows the tail and nothing else owns the scroll.
    private var pinsToBottom: Bool {
        isFollowing && !isUserScrolling && !isAnimatingScroll && !collectionView.isTracking
    }

    // MARK: Data

    func update(model: TranscriptModel, environment newEnvironment: TranscriptCellEnvironment) {
        let reconfigureAll = newEnvironment.needsReconfigure(from: environment)
        environment = newEnvironment
        if let epoch = store?.timeline.epoch, epoch != lastEpoch {
            if lastEpoch != nil { rowFrames.reset() }
            lastEpoch = epoch
        }
        if model.items != items {
            applyStructuralChange(model)
        } else {
            var changed: [Int] = []
            for index in model.entries.indices where model.entries[index] != entries[index] {
                changed.append(index)
                if case .turn(let before) = entries[index], case .turn(let after) = model.entries[index],
                    before.turn.phase == .running, after.turn.phase != .running
                {
                    settlingTurn = (items[index], Date.now.addingTimeInterval(1))
                }
            }
            if !changed.isEmpty {
                entries = model.entries
                for index in changed { reconfigureVisible(index) }
            }
        }
        if reconfigureAll {
            for indexPath in collectionView.indexPathsForVisibleItems {
                reconfigureVisible(indexPath.item)
            }
        }
    }

    /// Items were added or removed. The change is a run in the middle of the list (an older page after
    /// the history slot, a new turn before the trailing cards), applied as one batch with no animation.
    /// Unless the reader follows the tail, the first visible item keeps its place on screen.
    private func applyStructuralChange(_ model: TranscriptModel) {
        let old = items
        let oldEntries = entries
        let new = model.items
        let cv = collectionView

        var prefix = 0
        let shortest = min(old.count, new.count)
        while prefix < shortest, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        let deleted = prefix..<(old.count - suffix)
        let inserted = prefix..<(new.count - suffix)

        var newIndex: [TranscriptItemID: Int] = [:]
        newIndex.reserveCapacity(new.count)
        for (index, id) in new.enumerated() where newIndex[id] == nil { newIndex[id] = index }

        let anchor = isFollowing ? nil : captureAnchor(present: newIndex)
        let batch = didInitialLayout && cv.window != nil && deleted.count + inserted.count <= 400
            && newIndex.count == new.count
        isApplyingStructuralChange = true
        defer { isApplyingStructuralChange = false }

        if batch {
            UIView.performWithoutAnimation {
                cv.performBatchUpdates {
                    self.items = new
                    self.entries = model.entries
                    self.indexByID = newIndex
                    self.layout.itemsDidChange()
                    if !deleted.isEmpty {
                        cv.deleteItems(at: deleted.map { IndexPath(item: $0, section: 0) })
                    }
                    if !inserted.isEmpty {
                        cv.insertItems(at: inserted.map { IndexPath(item: $0, section: 0) })
                    }
                }
            }
            // Kept items whose content changed in the same update.
            for index in 0..<prefix where oldEntries[index] != model.entries[index] {
                reconfigureVisible(index)
            }
            for step in 0..<suffix {
                let oldIndex = old.count - 1 - step
                let newIndex = new.count - 1 - step
                if oldEntries[oldIndex] != model.entries[newIndex] { reconfigureVisible(newIndex) }
            }
        } else {
            items = new
            entries = model.entries
            indexByID = newIndex
            layout.itemsDidChange()
            cv.reloadData()
        }

        if let anchor {
            cv.layoutIfNeeded()
            restore(anchor)
        } else if pinsToBottom {
            cv.layoutIfNeeded()
            pinIfNeeded()
        }
    }

    private struct Anchor {
        var id: TranscriptItemID
        /// The item's top relative to the content offset.
        var screenY: CGFloat
    }

    /// The first item on screen (below the bars) that survives the change.
    private func captureAnchor(present: [TranscriptItemID: Int]) -> Anchor? {
        guard didInitialLayout, !items.isEmpty else { return nil }
        let cv = collectionView
        let top = cv.contentOffset.y + cv.contentInset.top
        var index = layout.firstIndex(withMaxYAtLeast: top + 1)
        let end = min(items.count, index + 40)
        while index < end {
            let id = items[index]
            if id != .historyStart, present[id] != nil, let frame = layout.frame(at: index) {
                return Anchor(id: id, screenY: frame.minY - cv.contentOffset.y)
            }
            index += 1
        }
        return nil
    }

    private func restore(_ anchor: Anchor) {
        guard let index = indexByID[anchor.id], let frame = layout.frame(at: index) else { return }
        let target = clamp(frame.minY - anchor.screenY)
        let cv = collectionView
        if abs(cv.contentOffset.y - target) > 0.25 { setOffset(target) }
    }

    private func reconfigureVisible(_ index: Int) {
        guard
            let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
                as? TranscriptCell
        else { return }
        configure(cell, at: index)
        cell.invalidateIntrinsicContentSize()
    }

    private func configure(_ cell: TranscriptCell, at index: Int) {
        guard entries.indices.contains(index), let environment else { return }
        let entry = entries[index]
        cell.fixedHeight = entry == .historyStart ? TranscriptView.historyStartSlotHeight : nil
        cell.contentConfiguration = UIHostingConfiguration {
            TranscriptCellRoot(entry: entry, env: environment)
        }
        .margins(.all, 0)
        .minSize(width: 0, height: 0)
    }

    // MARK: Heights

    func columnWidthChanged() {
        estimateCache.removeAll()
    }

    /// A first guess for an item not yet measured at this width: the remembered height of a settled
    /// turn (W8), else a guess from its text. Only the scroll bar and long jumps ever see a guess: rows
    /// above the reader are compensated when they measure, rows near the reader measure before display.
    func estimatedHeight(at index: Int, column: CGFloat) -> CGFloat {
        guard entries.indices.contains(index) else { return 44 }
        switch entries[index] {
        case .historyStart: return TranscriptView.historyStartSlotHeight
        case .permissions: return 180
        case .resolvedPermissions: return 22
        case .backgroundWork: return 44
        case .turn(let row):
            let turn = row.turn
            if let cached = estimateCache[turn.id] { return cached }
            let estimate: CGFloat
            if let remembered = heightMemory.height(for: fingerprint(turn, column: column)) {
                estimate = CGFloat(remembered)
            } else {
                estimate = Self.guessHeight(turn, column: column)
            }
            estimateCache[turn.id] = estimate
            return estimate
        }
    }

    private static func guessHeight(_ turn: Turn, column: CGFloat) -> CGFloat {
        let charsPerLine = max(Double(column) / 8.2, 16)
        func lines(_ text: String) -> Double {
            max(1, (Double(text.utf8.count) / charsPerLine * 1.15).rounded(.up))
        }
        var height: Double = 36 + 40
        if let row = turn.userMessage, case .userMessage(let message) = row.item {
            height += 24 + lines(message.text) * 22 + 14
        }
        for segment in turn.segments {
            switch segment {
            case .prose(let row):
                if case .assistantMessage(let message) = row.item {
                    height += lines(message.text) * 25 + 14
                    height += Double(codeLineCount(in: message.text)) * 18
                    height += Double(imageCount(in: message.text)) * 220
                }
            case .notice:
                height += 44
            case .work:
                // A collapsed section header and the gap after it.
                height += 52
            case .todo:
                break
            }
        }
        if turn.changeSummary != nil, turn.phase != .running { height += 36 }
        return CGFloat(min(max(height, 60), 8000))
    }

    /// Lines inside fenced code blocks (the fence lines included: they draw the block's frame).
    private static func codeLineCount(in text: String) -> Int {
        guard text.contains("```") else { return 0 }
        var inside = false
        var count = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.drop(while: { $0 == " " }).hasPrefix("```") {
                inside.toggle()
                count += 1
            } else if inside {
                count += 1
            }
        }
        return count
    }

    /// Markdown image references (`![`).
    private static func imageCount(in text: String) -> Int {
        guard text.contains("![") else { return 0 }
        return text.components(separatedBy: "![").count - 1
    }

    private func fingerprint(_ turn: Turn, column: CGFloat) -> String {
        TurnHeightMemory.fingerprint(
            epoch: store?.timeline.epoch ?? "", turnId: turn.id, firstRowSeq: turn.firstRowSeq,
            lastRowSeq: turn.lastRowSeq, columnWidth: Double(column),
            dynamicType: environment?.dynamicType ?? "")
    }

    /// A settled turn's real height is remembered for the next open (W8), written off main and at most
    /// every five seconds.
    func didMeasure(index: Int, height: CGFloat) {
        guard entries.indices.contains(index), case .turn(let row) = entries[index],
            row.turn.phase != .running, height > 1
        else { return }
        let key = fingerprint(row.turn, column: layout.columnWidth)
        guard heightMemory.record(key: key, height: Double(height)) else { return }
        guard Date.now.timeIntervalSince(lastHeightSave) > 5 else { return }
        lastHeightSave = Date.now
        TurnHeightStore.save(heightMemory.persisted)
    }

    /// A cell changed height: keep what the reader looks at where it is, in the same layout pass. While
    /// the end is pinned the pin does it instead.
    ///
    /// Upstream's rule (LegendList `maintainVisibleContentPosition` with Paseo's patch): the anchor is
    /// the first cell wholly on screen below the reader's line, locked for the pass (`anchorLock`). A
    /// cell before it (above the line, or cut off by it) changes height by moving the offset by the
    /// whole delta (`contentOffsetAdjustment`), so the anchor and everything below it stay put: an
    /// older turn measured or settling in the overscan, the top of a turn the reader is scrolling into.
    /// The anchor and the cells after it grow downward and move nothing above them. When no cell is
    /// wholly on screen (one turn taller than the screen), the cell under the line is the anchor and
    /// grows downward too.
    ///
    /// - The tapped cell is a disclosure opening where the reader looks: its top stays (upstream holds
    ///   the toggled row).
    /// - A turn that just finished folds the work above its answer away: the turn's end stays put,
    ///   on a net shrink only (otherwise the answer would move by the footer and changes card
    ///   added below it instead of by the smaller fold above it).
    func compensatesResize(of frame: CGRect, at index: Int, delta: CGFloat) -> Bool {
        guard !pinsToBottom else { return false }
        let cv = collectionView
        let readerTop = cv.contentOffset.y + cv.contentInset.top
        guard frame.minY < readerTop - 0.5, cv.contentOffset.y + delta >= -cv.contentInset.top,
            items.indices.contains(index), entries.indices.contains(index)
        else { return false }
        if let settling = settlingTurn, settling.until > Date.now, items[index] == settling.id {
            settlingTurn = nil
            return delta < 0
        }
        if Date.now < resizeAnimationUntil, items[index] == tappedItemID { return false }
        return index < anchorIndex(readerTop: readerTop)
    }

    /// The pass's anchor: the first cell wholly between the reader's line and the bottom bars, else the
    /// cell under the line. Chosen once per layout pass from the frames the pass started with, so the
    /// cells measured in one pass all compensate against the same row (upstream's anchor lock: without
    /// it, a cell measured early in the pass moves the frames the next decision reads).
    private func anchorIndex(readerTop: CGFloat) -> Int {
        if let anchorLock, let index = indexByID[anchorLock] { return index }
        let cv = collectionView
        let readerBottom = cv.contentOffset.y + cv.bounds.height - cv.contentInset.bottom
        let underLine = layout.firstIndex(withMaxYAtLeast: readerTop)
        var anchor = underLine
        while let frame = layout.frame(at: anchor), frame.minY < readerBottom {
            if frame.height > 0, frame.minY >= readerTop - 0.5, frame.maxY <= readerBottom + 0.5 { break }
            anchor += 1
        }
        // Nothing wholly on screen: the cell under the line holds.
        if layout.frame(at: anchor).map({ $0.minY >= readerBottom }) ?? true { anchor = underLine }
        if items.indices.contains(anchor) { anchorLock = items[anchor] }
        return anchor
    }

    // MARK: Insets

    /// The bars, the keyboard and the composer, measured by SwiftUI. While the reader follows the tail
    /// the end moves with them, in the same animation as the keyboard.
    func setInsets(_ edges: EdgeInsets, animation: Animation?) {
        let cv = collectionView
        let insets = UIEdgeInsets(
            top: edges.top + TranscriptContainerView.overscan, left: 0, bottom: edges.bottom, right: 0)
        let horizontal = (left: edges.leading, right: edges.trailing)
        if horizontal != layout.horizontalInsets {
            layout.horizontalInsets = horizontal
            layout.invalidateLayout()
        }
        guard insets != cv.contentInset else { return }
        let first = !insetsApplied
        insetsApplied = true
        let apply = { [self] in
            let wasPinned = pinsToBottom
            cv.contentInset = insets
            cv.verticalScrollIndicatorInsets = UIEdgeInsets(
                top: insets.top, left: 0, bottom: insets.bottom, right: 0)
            if first || wasPinned {
                cv.layoutIfNeeded()
                pinIfNeeded(glides: false)
            }
        }
        if first {
            apply()
        } else if let animation, !reduceMotion {
            UIView.animate(animation, changes: apply)
        } else if let keyboard = keyboardAnimation, keyboard.until > Date.now, !reduceMotion {
            UIView.animate(
                withDuration: keyboard.duration, delay: 0,
                options: [
                    UIView.AnimationOptions(rawValue: UInt(keyboard.curve) << 16),
                    .beginFromCurrentState, .allowUserInteraction,
                ],
                animations: apply)
        } else {
            apply()
        }
        lastDistanceFromContentBottom = metrics.distanceFromContentBottom
    }

    // MARK: Layout pass

    func collectionViewDidLayout() {
        didInitialLayout = true
        anchorLock = nil
        pinIfNeeded()
        if items.count > 1 { prewarmWebOnce() }
        let cv = collectionView
        if cv.contentSize.height != lastContentHeight || cv.bounds.height != lastBoundsHeight {
            lastContentHeight = cv.contentSize.height
            lastBoundsHeight = cv.bounds.height
            metricsChanged()
        }
    }

    /// `glides`: a disclosure's resize may animate the pin. Off inside the keyboard's own animation.
    private func pinIfNeeded(glides: Bool = true) {
        guard pinsToBottom, didInitialLayout else { return }
        let cv = collectionView
        let target = maxOffsetY
        guard abs(cv.contentOffset.y - target) > 0.25 else { return }
        if glides, animatesResizes {
            // A disclosure at the end: the end follows it in the content's own curve.
            UIView.animate(Motion.disclosure.animation, changes: {
                cv.contentOffset = CGPoint(x: 0, y: target)
            })
        } else if glides, followsStreamGrowth(by: target - cv.contentOffset.y) {
            // A reply growing at the end: a new line slides up into place instead of the whole
            // transcript jumping a line per reveal step. Short, so it never trails the text.
            UIView.animate(
                withDuration: Self.streamFollowDuration, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { cv.contentOffset = CGPoint(x: 0, y: target) })
        } else {
            cv.contentOffset = CGPoint(x: 0, y: target)
        }
    }

    /// A streamed line moves the end by a plain offset write in the same layout pass (Fish Pocket does
    /// the same: no animation on follow). Flip to `true` to A/B the short glide on a device.
    private static let glidesStreamFollow = false
    /// How long the end takes to catch up with a streamed line (only with `glidesStreamFollow`).
    private static let streamFollowDuration: TimeInterval = 0.16
    /// Growth past this is a jump (a block, a card, history), not a streamed line: it lands at once.
    private static let streamFollowMaxStep: CGFloat = 96

    /// A small downward growth while a turn streams, with nothing else animating the content.
    private func followsStreamGrowth(by delta: CGFloat) -> Bool {
        let keyboardMoving = (keyboardAnimation?.until ?? .distantPast) > Date.now
        guard Self.glidesStreamFollow, store?.activeTurnId != nil, !reduceMotion, !keyboardMoving
        else { return false }
        return delta > 0 && delta <= Self.streamFollowMaxStep
    }

    // MARK: Scroll

    private func metricsChanged() {
        guard let controller else { return }
        let m = metrics
        let delta = m.offsetY - lastOffsetY
        lastOffsetY = m.offsetY

        if isUserScrolling {
            let changed = headerReveal.scroll(
                by: delta,
                revealDistance: TranscriptHeader.revealDistance(viewport: stableScreen),
                hideDistance: TranscriptHeader.hideDistance,
                roomAbove: m.offsetY,
                roomBelow: m.distanceFromBottom,
                canScroll: m.canScroll)
            if changed { publishHeader() }
        } else if !m.canScroll, !isAnimatingScroll {
            revealHeader()
        }

        // "Back to the end" flips on the reader's motion or at rest, and only when the content moved:
        // the keyboard animating the insets never flashes it (H2 §2, J3 §3).
        if !isAnimatingScroll, m.distanceFromContentBottom != lastDistanceFromContentBottom {
            decideBackToEnd(m, controller: controller)
        }
        lastDistanceFromContentBottom = m.distanceFromContentBottom

        let now = Date.now
        if now.timeIntervalSince(lastTick) >= Self.readingReportInterval {
            lastTick = now
            reportReadingPosition()
            if isUserScrolling { revealTurnRail() }
        }

        settleHistoryStart()
        loadOlderIfNeeded(m)
        if historyGeometry(m)?.isUnderfilled == true, store?.timeline.hasOlder == true {
            startHistoryTicker()
        }
    }

    /// The scroll came to rest: the follow, the button and the history decide here.
    private func settled() {
        guard let controller else { return }
        let m = metrics
        reportReadingPosition()
        if !controller.isFollowing, !controller.anchoringToAnswer,
            m.distanceFromBottom <= Self.followSlack
        {
            controller.isFollowing = true
        }
        decideBackToEnd(m, controller: controller)
        settleHistoryStart()
        loadOlderIfNeeded(m)
        prewarmWebOnce()
    }

    private func decideBackToEnd(_ m: Metrics, controller: ChatController) {
        var state = controller.backToEnd
        state.update(
            distanceFromContentBottom: m.distanceFromContentBottom, screen: stableScreen,
            isFollowing: controller.isFollowing)
        if controller.backToEnd != state { controller.backToEnd = state }
    }

    private func publishHeader() {
        guard let controller else { return }
        let hidden = headerReveal.isHidden
        if controller.headerHidden != hidden { controller.headerHidden = hidden }
    }

    private func revealHeader() {
        guard headerReveal.reveal() else { return }
        publishHeader()
    }

    /// The position under the top of the screen, reported to the outline when it moves.
    private func reportReadingPosition() {
        guard let store, let controller else { return }
        var seq: Int?
        if let index = topVisibleTurnIndex(), case .turn(let row) = entries[index] {
            seq = row.turn.firstRowSeq
        }
        if seq == nil, controller.isFollowing { seq = controller.lastPromptSeq }
        if let reported = reportedReadingAnchor, reported == seq { return }
        reportedReadingAnchor = .some(seq)
        store.promptOutline.reportReadingPosition(anchorSeq: seq)
    }

    /// The first turn whose bottom is below the top of the visible area.
    private func topVisibleTurnIndex() -> Int? {
        let cv = collectionView
        var index = layout.firstIndex(withMaxYAtLeast: cv.contentOffset.y + cv.contentInset.top + 1)
        while index < entries.count {
            if case .turn = entries[index] { return index }
            index += 1
        }
        return nil
    }

    func revealTurnRail() {
        guard ChatOutlineRail.promptRailEnabled, controller?.outlineAvailable == true else { return }
        if !ui.turnNavVisible { ui.turnNavVisible = true }
        turnNavDeadline = Date.now.addingTimeInterval(TranscriptView.turnNavIdleDuration)
        guard turnNavTask == nil else { return }
        turnNavTask = Task { [weak self] in
            while let self, let deadline = self.turnNavDeadline, !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { break }
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard let self, !Task.isCancelled else { return }
            self.turnNavDeadline = nil
            self.turnNavTask = nil
            self.ui.turnNavVisible = false
        }
    }

    private func prewarmWebOnce() {
        guard !didPrewarmWeb else { return }
        didPrewarmWeb = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            for _ in 0..<10 where self.isUserScrolling {
                try? await Task.sleep(for: .milliseconds(300))
            }
            RichWebSnapshotRenderer.shared.prewarm()
        }
    }

    // MARK: Programmatic scrolls

    /// An animated scroll the reader did not start. Reduce Motion moves at once.
    private func animateScroll(to y: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        let cv = collectionView
        let target = clamp(y)
        if abs(target - cv.contentOffset.y) < 1 || reduceMotion {
            setOffset(target)
            completion?()
            return
        }
        isAnimatingScroll = true
        animationCompletion = completion
        animationToken += 1
        let token = animationToken
        cv.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        // UIKit does not report the end of an animation another offset change cut short: the flag never
        // outlives the animation it stands for.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, self.isAnimatingScroll, self.animationToken == token else { return }
            self.animationEnded()
        }
    }

    /// Sets the offset at once. An animated scroll in progress is over: it would otherwise keep the pin off.
    private func setOffset(_ y: CGFloat) {
        if isAnimatingScroll {
            isAnimatingScroll = false
            animationCompletion = nil
        }
        collectionView.contentOffset = CGPoint(x: 0, y: y)
    }

    private func animationEnded() {
        guard isAnimatingScroll else { return }
        isAnimatingScroll = false
        let completion = animationCompletion
        animationCompletion = nil
        pinIfNeeded()
        completion?()
        settled()
    }

    /// The end, gliding when it is near and landing a screen short first when it is far, so the glide
    /// covers built rows.
    func scrollToEnd(animated: Bool) {
        revealToken += 1
        let cv = collectionView
        cv.layoutIfNeeded()
        let distance = maxOffsetY - cv.contentOffset.y
        guard distance > 0.5 else {
            pinIfNeeded()
            return
        }
        if !animated || reduceMotion {
            setOffset(maxOffsetY)
            return
        }
        if distance > visibleHeight * 1.5 {
            setOffset(maxOffsetY - visibleHeight * 0.8)
            cv.layoutIfNeeded()
        }
        animateScroll(to: maxOffsetY)
    }

    /// A send goes to the end and stays there while the reply streams (upstream `message-sent`
    /// sticky-bottom). The pin keeps it there; a finger takes it back.
    func followEndAfterSend() {
        guard let controller else { return }
        if !controller.isFollowing { controller.isFollowing = true }
        revealHeader()
        scrollToEnd(animated: true)
    }

    /// "Back to the end".
    func returnToEnd() {
        revealHeader()
        scrollToEnd(animated: true)
    }

    /// Focusing the composer is a wish to be at the end (H2 §2): within a screen the transcript glides
    /// there and follows; further up the reader's place wins.
    func endScrollRequested() {
        guard let controller else { return }
        let m = metrics
        guard m.distanceFromBottom > Self.followSlack else {
            if !controller.isFollowing { controller.isFollowing = true }
            return
        }
        guard m.distanceFromBottom <= stableScreen else {
            if controller.isFollowing { controller.isFollowing = false }
            decideBackToEnd(m, controller: controller)
            return
        }
        controller.isFollowing = true
        scrollToEnd(animated: true)
    }

    enum Placement {
        case top
        case center(CGFloat)
    }

    /// Where the content offset must be for a row (or its turn) to sit at `placement`.
    private func targetOffset(index: Int, rowSeq: Int?, placement: Placement) -> CGFloat? {
        guard let item = layout.frame(at: index) else { return nil }
        var rect = item
        if let rowSeq, let row = rowFrames.frame(of: rowSeq), row.minY >= -1,
            row.maxY <= item.height + 1
        {
            rect = CGRect(
                x: item.minX + row.minX, y: item.minY + row.minY, width: row.width, height: row.height)
        }
        let top = collectionView.contentInset.top
        switch placement {
        case .top:
            return clamp(rect.minY - top - 12)
        case .center(let fraction):
            let visible = visibleHeight
            if rect.height <= visible * 0.9 {
                return clamp(rect.midY - top - visible / 2)
            }
            return clamp(rect.minY + rect.height * fraction - top - visible * fraction)
        }
    }

    /// Brings an item (and a row inside it) to `placement`. A far target is landed next to without
    /// animation, so its rows are built and measured; then, once the rows inside the cell have reported
    /// where they are, the last stretch glides. After the glide the target is checked once more against
    /// the measured layout.
    private func reveal(
        _ resolve: @escaping @MainActor () -> (index: Int, rowSeq: Int?)?,
        placement: Placement, animated: Bool, completion: (@MainActor () -> Void)? = nil
    ) {
        revealToken += 1
        let token = revealToken
        let cv = collectionView
        cv.layoutIfNeeded()
        guard let first = resolve(), let target = targetOffset(
            index: first.index, rowSeq: first.rowSeq, placement: placement)
        else { return }
        let glide = animated && !reduceMotion
        let distance = target - cv.contentOffset.y
        if !glide || abs(distance) > visibleHeight * 1.5 {
            let lead: CGFloat = glide ? (distance > 0 ? -1 : 1) * visibleHeight * 0.6 : 0
            setOffset(clamp(target + lead))
            cv.layoutIfNeeded()
        }
        Task { [weak self] in
            // Two frames: the cells laid out above report their rows' frames from SwiftUI.
            try? await Task.sleep(for: .milliseconds(34))
            guard let self, token == self.revealToken else { return }
            self.collectionView.layoutIfNeeded()
            guard let current = resolve(), let final = self.targetOffset(
                index: current.index, rowSeq: current.rowSeq, placement: placement)
            else { return }
            let finish: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(34))
                    guard token == self.revealToken else { return }
                    self.collectionView.layoutIfNeeded()
                    if let settled = resolve(), let exact = self.targetOffset(
                        index: settled.index, rowSeq: settled.rowSeq, placement: placement),
                        abs(exact - self.collectionView.contentOffset.y) > 2
                    {
                        self.setOffset(exact)
                    }
                    self.rearmHistoryIfNearTop()
                    completion?()
                }
            }
            if glide {
                self.animateScroll(to: final, completion: finish)
            } else {
                self.setOffset(final)
                finish()
            }
        }
    }

    // MARK: Jumps and find

    /// A prompt or media row (`row:<seqEnd>`) or a turn id. Jumping back releases the tail-follow.
    func jumpToTurn(_ id: String) {
        guard let store, let controller else { return }
        if controller.isFollowing { controller.isFollowing = false }
        if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
        let seq: Int?
        let rowSeq: Int?
        if id.hasPrefix("row:"), let value = Int(id.dropFirst(4)) {
            seq = value
            rowSeq = value
        } else {
            seq = store.turns.first { $0.id == id }?.firstRowSeq
            rowSeq = nil
        }
        guard let seq else {
            PaseoPerf.mark("jump.noTurn")
            return
        }
        let resolve: @MainActor () -> (index: Int, rowSeq: Int?)? = { [weak self] in
            guard let self, let store = self.store else { return nil }
            let turns = store.turns
            guard
                let turnIndex = turns.firstIndex(where: { $0.containsRow(seqEnd: seq) })
                    ?? turns.lastIndex(where: { ($0.firstRowSeq ?? Int.max) <= seq }),
                let index = self.indexByID[.turn(turns[turnIndex].id)]
            else { return nil }
            return (index, rowSeq)
        }
        guard let target = resolve(), case .turn(let row) = entries[target.index] else {
            PaseoPerf.mark("jump.noTurn")
            return
        }
        revealHeader()
        showLandingLine(for: row.turn.id)
        reveal(resolve, placement: .top, animated: true)
    }

    private func showLandingLine(for id: String) {
        ui.landingTurnId = id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TranscriptView.landingDuration))
            guard let self, self.ui.landingTurnId == id else { return }
            self.ui.landingTurnId = nil
        }
    }

    /// A step in find: the row of the match, fetched first when it is not loaded (upstream
    /// `chat-find/model.ts` `navigate`), centred, then flashed.
    func scrollToMatch(_ jump: FindJump) {
        guard let store, let controller else { return }
        if controller.isFollowing { controller.isFollowing = false }
        if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
        guard let target = FindNavigation.target(in: store.turns, seq: jump.seq, role: jump.role)
        else {
            findFetchTask?.cancel()
            findFetchTask = Task { [weak self] in
                let loaded = await store.loadTimelineWindow(aroundSeq: jump.seq)
                guard let self, !Task.isCancelled, controller.find.isOpen else { return }
                guard loaded,
                    FindNavigation.target(in: store.turns, seq: jump.seq, role: jump.role) != nil
                else {
                    controller.find.rowSeq = nil
                    return
                }
                self.scrollToMatch(jump)
            }
            return
        }
        if controller.find.rowSeq != target.rowSeqEnd { controller.find.rowSeq = target.rowSeqEnd }
        if !controller.find.moved { controller.find.moved = true }
        let fraction = FindNavigation.text(of: target, in: store.turns).flatMap { text in
            text.count > FindNavigation.longMessage
                ? FindNavigation.occurrenceFraction(of: store.search.query, in: text, last: jump.backward)
                : nil
        }
        let seq = jump.seq
        let role = jump.role
        reveal(
            { [weak self] in
                guard let self, let store = self.store,
                    let found = FindNavigation.target(in: store.turns, seq: seq, role: role),
                    store.turns.indices.contains(found.turnIndex),
                    let index = self.indexByID[.turn(store.turns[found.turnIndex].id)]
                else { return nil }
                return (index, found.rowSeqEnd)
            },
            placement: .center(fraction ?? 0.5), animated: true,
            completion: { [weak controller] in controller?.flash(target.rowSeqEnd) })
    }

    /// Find opened: remember the turn the reader was on (or the end), so closing find can go back.
    func findOpened() {
        guard let controller else { return }
        let atEnd = controller.isFollowing
            || metrics.distanceFromContentBottom <= Self.endMargin
        var anchorSeq: Int?
        if !atEnd, let index = topVisibleTurnIndex(), case .turn(let row) = entries[index] {
            anchorSeq = row.turn.firstRowSeq
        }
        controller.find.anchorSeq = anchorSeq
        if controller.find.moved { controller.find.moved = false }
    }

    /// Find closed: back to where the reader was, if stepping through matches moved them.
    func findClosed() {
        revealToken += 1
        findFetchTask?.cancel()
        findFetchTask = nil
        guard let store, let controller, controller.find.moved else { return }
        controller.find.moved = false
        if let seq = controller.find.anchorSeq,
            FindNavigation.firstTurnIndex(endingAtOrAfter: seq, in: store.turns) != nil
        {
            reveal(
                { [weak self] in
                    guard let self, let store = self.store,
                        let turnIndex = FindNavigation.firstTurnIndex(endingAtOrAfter: seq, in: store.turns),
                        let index = self.indexByID[.turn(store.turns[turnIndex].id)]
                    else { return nil }
                    return (index, nil)
                }, placement: .top, animated: true)
        } else {
            controller.isFollowing = true
            scrollToEnd(animated: true)
        }
    }

    // MARK: Older history

    private func historyGeometry(_ m: Metrics) -> HistoryStartGeometry? {
        guard let store, m.viewportHeight > 0 else { return nil }
        return history.geometry(
            contentHeight: Double(m.contentHeight), viewportHeight: Double(m.viewportHeight),
            offsetY: Double(m.offsetY),
            prefetchDistance: Double(m.viewportHeight * Self.prefetchScreens), store: store)
    }

    private var isHistoryLoadingOperation: Bool {
        history.state.status == .loading || history.state.status == .settling
    }

    /// Fetched ahead: the page is on its way while the reader is still screens from the top, and the
    /// prepend is compensated inside the batch update, so a flick toward the top is never stopped.
    private func loadOlderIfNeeded(_ m: Metrics) {
        guard m.offsetY <= m.viewportHeight * Self.prefetchScreens, !historyLoadInFlight,
            let geometry = historyGeometry(m), let generation = history.update(geometry)
        else { return }
        requestOlderPage(generation: generation)
    }

    private func requestOlderPage(generation: Int) {
        guard let store else { return }
        historyLoadInFlight = true
        let cursor = store.timeline.startCursor
        startHistoryTicker()
        Task { [weak self] in
            await store.loadOlder()
            guard let self else { return }
            self.historyLoadInFlight = false
            // Applied: a page prepended, or the start of the conversation is confirmed.
            self.history.loadCompleted(
                generation: generation,
                applied: store.timeline.startCursor != cursor || !store.timeline.hasOlder)
            _ = self.history.update(self.historyGeometry(self.metrics))
            self.settleHistoryStart()
        }
    }

    private func settleHistoryStart() {
        guard history.state.status == .settling else { return }
        history.settle(historyGeometry(metrics))
    }

    /// "Try again": the machine is ready again and asked for the page now.
    func retryOlderHistory() {
        history.rearm()
        let m = metrics
        guard !historyLoadInFlight, let geometry = historyGeometry(m),
            let generation = history.update(geometry)
        else { return }
        requestOlderPage(generation: generation)
    }

    /// A jump that lands near the top asks for older history (a jump is no finger, and a filled list
    /// waits for one).
    private func rearmHistoryIfNearTop() {
        let m = metrics
        guard m.viewportHeight > 0, m.offsetY <= m.viewportHeight * Self.prefetchScreens else { return }
        history.rearm()
        loadOlderIfNeeded(m)
    }

    /// While the content is shorter than the screen (no scroll frames come) or a page is loading (the
    /// watchdog needs a clock), look again twice a second. Stops itself when neither holds.
    private func startHistoryTicker() {
        guard historyTicker == nil else { return }
        historyTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                let m = self.metrics
                let loading = self.isHistoryLoadingOperation
                let underfilled = self.historyGeometry(m)?.isUnderfilled == true
                    && self.store?.timeline.hasOlder == true
                guard loading || underfilled else {
                    self.historyTicker = nil
                    return
                }
                if loading { _ = self.history.update(self.historyGeometry(m)) }
                self.settleHistoryStart()
                if !self.isUserScrolling { self.loadOlderIfNeeded(m) }
            }
        }
    }
}
// MARK: - Data source and delegate

extension TranscriptEngine: UICollectionViewDataSource, UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let reuse = items.indices.contains(indexPath.item)
            ? reuseIdentifier(for: items[indexPath.item]) : "transcript.empty"
        if registeredReuse.insert(reuse).inserted {
            collectionView.register(TranscriptCell.self, forCellWithReuseIdentifier: reuse)
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuse, for: indexPath)
        if let cell = cell as? TranscriptCell { configure(cell, at: indexPath.item) }
        return cell
    }

    /// The reuse pool for an item: the singletons' own, a turn's borrowed slot.
    private func reuseIdentifier(for id: TranscriptItemID) -> String {
        guard case .turn = id else { return id.reuseIdentifier }
        useClock += 1
        if let slot = slotOf[id] {
            slotUse[slot] = useClock
            return "transcript.slot.\(slot)"
        }
        var slot = slotOwner.count
        if slotOwner.count >= Self.cellSlots {
            var onScreen = Set<TranscriptItemID>()
            for indexPath in collectionView.indexPathsForVisibleItems
            where items.indices.contains(indexPath.item) {
                onScreen.insert(items[indexPath.item])
            }
            var oldest = Int.max
            for (index, owner) in slotOwner.enumerated() {
                if let owner, onScreen.contains(owner) { continue }
                if slotUse[index] < oldest {
                    oldest = slotUse[index]
                    slot = index
                }
            }
        }
        if slot < slotOwner.count {
            if let previous = slotOwner[slot] { slotOf[previous] = nil }
            slotOwner[slot] = id
            slotUse[slot] = useClock
        } else {
            slotOwner.append(id)
            slotUse.append(useClock)
        }
        slotOf[id] = slot
        return "transcript.slot.\(slot)"
    }

    /// The prose of turns about to scroll in is split, parsed and highlighted off the main actor.
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        var texts: [String] = []
        for indexPath in indexPaths where entries.indices.contains(indexPath.item) {
            if case .turn(let row) = entries[indexPath.item] {
                texts.append(contentsOf: ProseWarmup.proseTexts(of: row.turn))
            }
        }
        guard !texts.isEmpty else { return }
        ProseWarmup.startForMessages(texts, home: store?.agent?.cwd)
    }
}
extension TranscriptEngine: UICollectionViewDelegate, UIGestureRecognizerDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A finger takes the viewport from any jump or glide still on its way (upstream `beginUserScroll`).
        revealToken += 1
        if isAnimatingScroll {
            isAnimatingScroll = false
            animationCompletion = nil
        }
        if let controller {
            if controller.isFollowing { controller.isFollowing = false }
            if controller.anchoringToAnswer { controller.anchoringToAnswer = false }
        }
        // A finger re-arms older history (upstream strategy-native.tsx:571, `handleScrollBeginDrag`).
        history.rearm()
        revealTurnRail()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        metricsChanged()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settled() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settled()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        animationEnded()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        revealToken += 1
        if let controller, controller.isFollowing { controller.isFollowing = false }
        return true
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        settled()
        rearmHistoryIfNearTop()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
