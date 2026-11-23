#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

@MainActor
final class PaseoTerminalCoordinator: NSObject, TerminalViewDelegate {
    /// Activity bookkeeping writes view state at most this often, and never when the tab's dot
    /// would not change.
    static let activityInterval: CFTimeInterval = 0.5
    /// The keyboard and the key bar move the grid in animated steps. Each step resizes the
    /// emulator at once, so the PTY has to follow closely or a TUI keeps drawing for the old grid
    /// and erases the wrong lines. Sizes go out at most this often: the first at once, the last
    /// always.
    static let resizeInterval: CFTimeInterval = 0.05

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
    /// When the last size went to the PTY, for the resize throttle.
    private var lastResizeSent: CFTimeInterval = 0
    /// Parses live output off the main thread, in arrival order. SwiftTerm's `feed` is
    /// nonisolated and parses on the calling thread under the terminal lock; its own frame driver
    /// draws at the display's cadence. Parsing a TUI's frames on the main thread, behind a
    /// display-link coalescer of our own, cost a frame of latency and main-thread time per frame.
    private let feedQueue = DispatchQueue(label: "paseo.terminal.feed", qos: .userInteractive)
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
        // Live bytes already queued for the old attachment land before the reset below.
        feedQueue.sync {}
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
                    // A barrier: live bytes still queued are parsed first, then the snapshot
                    // replaces the screen.
                    self.isReplaying = true
                    self.feedQueue.sync {}
                    self.view?.resetToInitialState()
                case .output(let data):
                    // Replay bytes are parsed here, on the main actor: the replies they generate
                    // are then delivered inline, while `isReplaying` still suppresses them. Off the
                    // main thread they would arrive after the replay ended and reach the PTY.
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
                    self.onExit(error)
                }
            }
        }
    }

    /// A live output chunk: parsed on the feed queue as soon as it arrives. SwiftTerm marks the
    /// frame dirty and draws it on its next display tick, so keystroke echo and a TUI's frames
    /// both reach the screen one vsync later at most, and a burst costs the main thread nothing.
    private func receive(_ data: Data) {
        reportActivity(CACurrentMediaTime())
        guard let sender = view?.feedSender else { return }
        feedQueue.async { sender.feed(byteArray: ArraySlice(data)) }
    }

    /// Activity bookkeeping for the tab's dot: at most one view write per `activityInterval`,
    /// and the view drops the ones that would not change anything.
    private func reportActivity(_ now: CFTimeInterval) {
        guard now - lastActivityReport >= Self.activityInterval else { return }
        lastActivityReport = now
        onOutput()
    }

    // MARK: Resize

    /// Throttles a measured grid size to the PTY: sent at once when nothing went out in the last
    /// `resizeInterval`, otherwise at the end of that window with the newest size. A debounce
    /// held every size until the animation had stopped, which left the program drawing for the
    /// old grid for the whole animation.
    private func scheduleResize(_ size: TerminalSize) {
        guard attachedSize != size else {
            pendingResize = nil
            return
        }
        pendingResize = size
        guard resizeTask == nil else { return }
        let wait = lastResizeSent + Self.resizeInterval - CACurrentMediaTime()
        guard wait > 0 else {
            applyResize()
            return
        }
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.resizeTask = nil
            self.applyResize()
        }
    }

    /// Sends the throttled size, once the keyboard animation has settled and any replay has
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
        lastResizeSent = CACurrentMediaTime()
        if intent == .claim { claimed = true }
        attachedSize = size
        pendingResize = nil
    }
}
#endif
