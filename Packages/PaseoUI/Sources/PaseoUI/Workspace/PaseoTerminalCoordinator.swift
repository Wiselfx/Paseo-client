#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

@MainActor
final class PaseoTerminalCoordinator: NSObject, TerminalViewDelegate {
    /// A hidden tab parses its output at most this often: its emulator stays current (replies
    /// to the program's queries are late by at most this much) without drawing frames nobody
    /// sees. SwiftTerm suspends drawing only for a view out of the window, and a hidden tab stays
    /// in it so its screen survives.
    static let hiddenFeedInterval: Duration = .milliseconds(250)
    /// Activity bookkeeping writes view state at most this often, and never when the tab's dot
    /// would not change.
    static let activityInterval: CFTimeInterval = 0.5
    /// The keyboard and the key bar move the grid in animated steps; the size is sent once they
    /// have settled.
    static let resizeSettle: Duration = .milliseconds(120)
    /// A burst larger than this is fed at once rather than held back for a frame.
    static let maxBufferedBytes = 256 * 1024

    /// The coordinator whose terminal is on screen. Only one terminal is visible at a time, so a
    /// keyboard hand-off has exactly one place to go.
    private static weak var visibleTerminal: PaseoTerminalCoordinator?
    /// The keyboard is up on a terminal that just went hidden. It moves to the visible terminal at
    /// the end of this run loop turn, which is what keeps the keyboard from dropping and re-rising
    /// on a switch.
    private static var keyboardHandoff = false

    weak var store: TerminalsStore?
    weak var view: TerminalView?
    /// The scrollback the view was last configured with — live re-application on change.
    var appliedScrollback = PaseoTerminalScrollback.defaultValue
    /// The scheme the emulator's background was last resolved for (E2b lead fix).
    struct BackgroundKey: Equatable {
        var style: UIUserInterfaceStyle
        var pureBlack: Bool
    }
    var appliedBackground: BackgroundKey?
    /// The font size the view was last configured with — live re-application on a Code size
    /// change, without touching the emulator buffer (scrollback survives).
    var appliedFontSize = PaseoTerminalFont.baseSize

    private var terminalId: String?
    private var isVisible = true
    /// Whether this attachment has claimed the PTY size. The visible terminal claims on attach and
    /// on focus; every later geometry change from it is an `update`.
    private var claimed = false
    private var lastSize: TerminalSize?
    private var attachedId: String?
    /// The store's token for this attachment: teardown detaches only what this view opened.
    private var attachedToken: UUID?
    private var attachedSize: TerminalSize?
    private var isAttaching = false
    private var isReplaying = false
    private var pendingResize: TerminalSize?
    private var attachTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    /// Bytes received since the last feed. Live output only: replay bytes are barriers and go
    /// straight through.
    private var pendingBytes: [UInt8] = []
    private var flushLink: CADisplayLink?
    private var lastFeedTime: CFTimeInterval = 0
    /// One display frame, as the flush link last reported it (8.3 ms on ProMotion): a chunk that
    /// arrives inside a frame that already fed bytes waits for the next tick; a chunk after an
    /// idle frame feeds immediately. It was a fixed 60 Hz frame, which held every second chunk
    /// for a frame the 120 Hz link had already drawn.
    private var frameInterval: CFTimeInterval = 1.0 / 60.0
    /// The hidden tab's next batched feed, while one is scheduled.
    private var hiddenFlushTask: Task<Void, Never>?
    private var lastActivityReport: CFTimeInterval = 0
    private var onOutput: () -> Void = {}
    private var onOpenLink: (TerminalLinkTarget) -> Void = { _ in }
    private var onExit: (String?) -> Void = { _ in }
    private var onAttach: (() -> Void)?
    private var onCancelUpload: (() -> Void)?
    private weak var keyBar: PaseoTerminalKeyBar?

    func configure(
        store: TerminalsStore, onOutput: @escaping () -> Void,
        onOpenLink: @escaping (TerminalLinkTarget) -> Void, onExit: @escaping (String?) -> Void,
        onAttach: (() -> Void)?, onCancelUpload: (() -> Void)?
    ) {
        self.store = store
        self.onOutput = onOutput
        self.onOpenLink = onOpenLink
        self.onExit = onExit
        self.onAttach = onAttach
        self.onCancelUpload = onCancelUpload
        let target = PaseoTerminalScrollback.current()
        if target != appliedScrollback {
            appliedScrollback = target
            view?.changeScrollback(target)
        }
        // SwiftTerm's `font` setter re-derives the bold/italic set and relayouts the cells;
        // the terminal buffer is untouched, so scrollback and live output survive a resize.
        let fontSize = PaseoTerminalFont.size()
        if fontSize != appliedFontSize {
            appliedFontSize = fontSize
            view?.font = PaseoTerminalFont.current()
        }
        applyToKeyBar()
    }

    /// Pushes the current upload snapshot and the closures into the key bar. Called from
    /// `configure` and `setUpload` so the bar always reflects the latest SwiftUI state.
    private func applyToKeyBar() {
        guard let keyBar else { return }
        keyBar.onAttach = onAttach
        keyBar.onCancelUpload = onCancelUpload
    }

    func setUpload(_ snapshot: TerminalUploadSnapshot?) {
        keyBar?.setUpload(snapshot)
    }

    func makeKeyBar(for view: TerminalView) -> PaseoTerminalKeyBar {
        let bar = PaseoTerminalKeyBar(terminalView: view) { [weak self] text in
            guard let self, let store = self.store, let terminalId = self.terminalId else { return }
            store.sendInput(text, to: terminalId)
        }
        bar.onAttach = { [weak self] in self?.onAttach?() }
        bar.onCancelUpload = { [weak self] in self?.onCancelUpload?() }
        keyBar = bar
        return bar
    }

    /// Switches the view to another terminal. Tears down the current attachment first.
    func select(terminalId: String?) {
        guard terminalId != self.terminalId else {
            if let lastSize { attachIfPossible(size: lastSize) }
            return
        }
        teardown()
        self.terminalId = terminalId
        if let lastSize { attachIfPossible(size: lastSize) }
    }

    /// Told by the page whether this terminal is the one on screen. Becoming visible takes the
    /// PTY size back (`claim` transfers ownership even when the dimensions are unchanged); going
    /// hidden never gives it away (`terminal-performance.md`, "Terminal size has one daemon-owned
    /// claimant").
    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        guard visible else {
            // A hidden terminal must not keep the keyboard: keystrokes would land on a grid nobody
            // can see. The hand-off itself runs at the end of this turn, after the visible terminal
            // has been told it is visible, so it does not matter which of the two views SwiftUI
            // updates first.
            if view?.isFirstResponder == true {
                Self.keyboardHandoff = true
                Self.scheduleKeyboardHandoff()
            }
            return
        }
        Self.visibleTerminal = self
        // What the tab held while hidden lands before its first visible frame.
        hiddenFlushTask?.cancel()
        hiddenFlushTask = nil
        flushPending()
        // Claim with the newest measured grid: a hidden tab holds its resizes until now.
        if let store, let terminalId, attachedId == terminalId, !isReplaying,
            let size = pendingResize ?? attachedSize
        {
            store.resize(terminalId, to: size, intent: .claim)
            claimed = true
            attachedSize = size
            pendingResize = nil
        }
        Self.scheduleKeyboardHandoff()
    }

    /// Hands the keyboard on once the whole update pass that switched terminals has run. One run
    /// loop hop per tab switch, never per frame.
    private static func scheduleKeyboardHandoff() {
        guard keyboardHandoff else { return }
        // The hop exists to run after this update pass, once every terminal has been told
        // whether it is visible.
        Task { @MainActor in handOverKeyboard() }
    }

    /// Becoming first responder resigns the hidden one in the same turn, so the keyboard stays up
    /// instead of animating away and back.
    private static func handOverKeyboard() {
        guard keyboardHandoff else { return }
        keyboardHandoff = false
        guard let target = visibleTerminal, target.isVisible,
            target.view?.isFirstResponder != true
        else { return }
        _ = target.view?.becomeFirstResponder()
    }

    /// Releases the subscription, cancels the byte pump and resets the emulator.
    func teardown() {
        attachTask?.cancel()
        attachTask = nil
        streamTask?.cancel()
        streamTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        flushLink?.invalidate()
        flushLink = nil
        hiddenFlushTask?.cancel()
        hiddenFlushTask = nil
        pendingBytes.removeAll(keepingCapacity: false)
        lastFeedTime = 0
        lastActivityReport = 0
        if let attachedId, let attachedToken { store?.detach(attachedId, token: attachedToken) }
        attachedId = nil
        attachedToken = nil
        attachedSize = nil
        claimed = false
        isAttaching = false
        isReplaying = false
        pendingResize = nil
        if Self.visibleTerminal === self { Self.visibleTerminal = nil }
        view?.resetToInitialState()
    }

    // MARK: TerminalViewDelegate

    func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
        onOpenLink(parseLinkTarget(request.link))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        let size = TerminalSize(rows: newRows, cols: newCols)
        lastSize = size
        attachIfPossible(size: size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // While the daemon's snapshot is streaming in, the parser may emit replies (DSR and
        // friends). Those must not reach the PTY; the replay preamble carries the real input
        // modes. User keystrokes in the replay window are dropped too; a replay takes
        // milliseconds.
        guard !isReplaying else { return }
        guard let store, let terminalId else { return }
        store.sendInput(Data(data), to: terminalId)
    }

    // MARK: Attachment

    private func attachIfPossible(size: TerminalSize) {
        guard let store, let terminalId else { return }
        if attachedId == terminalId {
            // The grid moves while the keyboard animates and while the key bar comes and goes.
            scheduleResize(size)
            return
        }
        if isAttaching {
            pendingResize = size
            return
        }
        isAttaching = true
        attachTask = Task { [weak self] in
            // Attaching with the measured size is what makes the daemon replay at this grid
            // (`terminal-rendering.md`: "The pane attaches with that size").
            let (token, stream) = await store.attachOwned(terminalId, size: size)
            guard let self else {
                store.detach(terminalId, token: token)
                return
            }
            self.attachTask = nil
            guard self.terminalId == terminalId, !Task.isCancelled else {
                // The user switched terminals (or the view went away) while the subscribe was
                // in flight.
                store.detach(terminalId, token: token)
                return
            }
            self.attachedId = terminalId
            self.attachedToken = token
            self.attachedSize = size
            self.isAttaching = false
            // Attaching claims the PTY size; later geometry changes travel as `update`. A
            // retained hidden tab must never take the grid from the visible one.
            if self.isVisible {
                store.resize(terminalId, to: size, intent: .claim)
                self.claimed = true
            }
            if let pending = self.pendingResize, pending != size {
                self.scheduleResize(pending)
            } else {
                self.pendingResize = nil
            }
            self.consume(stream, for: terminalId)
        }
    }

    // MARK: Feeding

    private func consume(_ stream: AsyncStream<TerminalOutput>, for terminalId: String) {
        streamTask = Task { [weak self] in
            for await output in stream {
                guard let self else { return }
                guard self.attachedId == terminalId else { break }
                switch output {
                case .replayBegin:
                    // A barrier: the snapshot replaces the screen, so bytes still waiting for the
                    // next frame are dropped rather than replayed under it.
                    self.isReplaying = true
                    self.pendingBytes.removeAll(keepingCapacity: true)
                    self.flushLink?.isPaused = true
                    self.view?.resetToInitialState()
                case .output(let data):
                    // Replay bytes are parsed in order and never held back: the replies they may
                    // generate have to stay suppressed until the last of them lands.
                    if self.isReplaying {
                        self.view?.feed(byteArray: ArraySlice(data))
                    } else {
                        self.receive(data)
                    }
                case .replayEnd:
                    self.isReplaying = false
                    // The grid is settled now: send the size the keyboard measured while the
                    // snapshot was parsing.
                    self.applyResize()
                case .exited(let error):
                    self.isReplaying = false
                    self.pendingBytes.removeAll(keepingCapacity: true)
                    self.flushLink?.isPaused = true
                    self.onExit(error)
                }
            }
        }
    }

    /// A live output chunk. Bursts are one `feed` per frame; a chunk that arrives after an idle
    /// frame goes straight through so keystroke echo never waits (upstream
    /// `terminal-performance.md`, "Coalescers are leading+trailing throttles").
    private func receive(_ data: Data) {
        let now = CACurrentMediaTime()
        reportActivity(now)
        if isVisible, pendingBytes.isEmpty, now - lastFeedTime >= frameInterval,
            data.count < Self.maxBufferedBytes
        {
            lastFeedTime = now
            view?.feed(byteArray: ArraySlice(data))
            return
        }
        pendingBytes.append(contentsOf: data)
        if pendingBytes.count >= Self.maxBufferedBytes {
            flushPending()
        } else {
            startFlushLink()
        }
    }

    /// Feeds everything received since the last frame, in one parser call.
    func flushPending() {
        guard !pendingBytes.isEmpty else {
            flushLink?.isPaused = true
            return
        }
        lastFeedTime = CACurrentMediaTime()
        // `feed` parses synchronously, so the batch buffer is reusable the moment it returns.
        view?.feed(byteArray: pendingBytes[...])
        pendingBytes.removeAll(keepingCapacity: true)
    }

    /// The display link's tick: learns the real frame length, then feeds the frame's bytes.
    func tick(_ link: CADisplayLink) {
        let duration = link.targetTimestamp - link.timestamp
        if duration > 0.001 { frameInterval = duration }
        flushPending()
    }

    private func startFlushLink() {
        guard isVisible else {
            scheduleHiddenFlush()
            return
        }
        if let flushLink {
            flushLink.isPaused = false
            return
        }
        let target = PaseoTickTarget()
        target.coordinator = self
        let link = CADisplayLink(target: target, selector: #selector(PaseoTickTarget.tick(_:)))
        link.preferredFrameRateRange = FrameRate.promotion
        link.add(to: .main, forMode: .common)
        flushLink = link
    }

    /// A hidden tab's bytes wait for one batched feed every `hiddenFeedInterval` instead of one
    /// per display frame.
    private func scheduleHiddenFlush() {
        flushLink?.isPaused = true
        guard hiddenFlushTask == nil else { return }
        hiddenFlushTask = Task { [weak self] in
            try? await Task.sleep(for: PaseoTerminalCoordinator.hiddenFeedInterval)
            guard !Task.isCancelled, let self else { return }
            self.hiddenFlushTask = nil
            self.flushPending()
        }
    }

    /// Activity bookkeeping for the tab's dot: at most one view write per `activityInterval`,
    /// and the view drops the ones that would not change anything.
    private func reportActivity(_ now: CFTimeInterval) {
        guard now - lastActivityReport >= Self.activityInterval else { return }
        lastActivityReport = now
        onOutput()
    }

    // MARK: Resize

    /// Debounces a measured grid size. A keyboard animation walks the terminal through a dozen
    /// heights, and each `sizeChanged` used to send its own resize RPC.
    private func scheduleResize(_ size: TerminalSize) {
        guard attachedSize != size else {
            pendingResize = nil
            return
        }
        pendingResize = size
        // Leading edge: the first change after a quiet period goes to the PTY at once. The stage
        // already holds the grid until the size has settled (`TerminalSettledFrame`), so this is
        // normally the only change, and the program redraws for the grid it is drawn on instead
        // of 120 ms later. Changes inside the window still trail.
        if resizeTask == nil { applyResize() }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: PaseoTerminalCoordinator.resizeSettle)
            guard !Task.isCancelled, let self else { return }
            self.resizeTask = nil
            self.applyResize()
        }
    }

    /// Sends the debounced size, once the keyboard animation has settled and any replay has
    /// finished. Replay geometry belongs to the parser queue, so a resize never lands inside one.
    private func applyResize() {
        guard let store, let terminalId, let size = pendingResize else { return }
        guard attachedId == terminalId, !isReplaying else { return }
        if attachedSize == size {
            pendingResize = nil
            return
        }
        // A hidden tab shares the stage's frame, so the keyboard resizes it too. Sending that
        // would make its program redraw for a grid nobody sees (and an inline redraw on the
        // normal screen is what duplicated output); it keeps the size and claims it when shown.
        guard isVisible else { return }
        // Only the terminal on screen claims the PTY size, and only once; later changes from this
        // attachment are updates. A retained hidden tab never claims.
        let intent: TerminalResizeIntent = isVisible && !claimed ? .claim : .update
        store.resize(terminalId, to: size, intent: intent)
        if intent == .claim { claimed = true }
        attachedSize = size
        pendingResize = nil
    }
}
#endif
