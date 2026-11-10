#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// A SwiftTerm `TerminalView` wired to `TerminalsStore`.
///
/// The store delivers an ordered byte stream per terminal (`AsyncStream<TerminalOutput>`);
/// this view resets the emulator on `.replayBegin`, feeds the ANSI bytes through SwiftTerm's
/// incremental parser, and reports keystrokes and resizes back through the store. While a
/// replay is parsing, generated replies (cursor-position reports and friends) are dropped so
/// the daemon does not receive phantom answers to its own snapshot queries.
///
/// Live output is coalesced to one `feed` per display frame, the way upstream's coalescer is a
/// leading+trailing throttle (`terminal-performance.md`, "Coalescers are leading+trailing
/// throttles"): the first chunk after an idle frame reaches the parser synchronously, the rest of
/// a burst waits for the next tick.
///
/// API used from SwiftTerm (checkout of 1.99.3): `TerminalView(frame:font:)` (iOS designated
/// init), `terminalDelegate`, `feed(byteArray:)`, `resetToInitialState()`,
/// `nativeForegroundColor`/`nativeBackgroundColor`, `changeScrollback(_:)`,
/// `sendKeyUp/Down/Left/Right`, `requestOpenLink(source:request:)` (link detection is on by
/// default), and the `TerminalViewDelegate` protocol (`sizeChanged`, `setTerminalTitle`,
/// `hostCurrentDirectoryUpdate`, `send`, `scrolled`, `rangeChanged`; the rest have defaults).
struct PaseoTerminalView: UIViewRepresentable {
    typealias UIViewType = TerminalView
    typealias Coordinator = PaseoTerminalCoordinator

    let store: TerminalsStore
    let terminalId: String?
    /// Whether this terminal is the one on screen. Only the visible terminal claims the PTY
    /// size; the retained hidden ones keep their streams but follow with `update`.
    let isVisible: Bool
    /// Called when the daemon detaches the stream. A non-nil error means observation failed and
    /// the process may still be running; nil means it ended cleanly.
    var onExit: (String?) -> Void = { _ in }
    /// Called after live output arrives, at most once per `activityInterval` per terminal.
    var onOutput: () -> Void = {}
    /// A link tap in the terminal; the page routes it (open the file, open the URL, …).
    var onOpenLink: (TerminalLinkTarget) -> Void = { _ in }
    /// The in-flight T14 upload shown in the key bar's progress row, or nil when idle.
    var upload: TerminalUploadSnapshot? = nil
    /// Called when the key bar's paperclip is tapped.
    var onAttach: (() -> Void)? = nil
    /// Called when the key bar's upload-row cancel button is tapped.
    var onCancelUpload: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero, font: PaseoTerminalFont.current())
        view.terminalDelegate = context.coordinator
        let scrollback = PaseoTerminalScrollback.current()
        view.changeScrollback(scrollback)
        context.coordinator.appliedScrollback = scrollback
        // The palette's ink on its canvas, in both schemes, so the terminal always reads as a
        // terminal.
        view.nativeForegroundColor = UIColor(Palette.ink)
        view.nativeBackgroundColor = UIColor(Palette.background)
        context.coordinator.view = view
        // The virtual key bar replaces SwiftTerm's built-in one: our keys, our haptics. Built once
        // here, never in `updateUIView`: rebuilding it would drop the keyboard's accessory view
        // and make the bar jump.
        view.inputAccessoryView = context.coordinator.makeKeyBar(for: view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.configure(
            store: store, onOutput: onOutput, onOpenLink: onOpenLink, onExit: onExit,
            onAttach: onAttach, onCancelUpload: onCancelUpload)
        context.coordinator.setVisible(isVisible)
        context.coordinator.select(terminalId: terminalId)
        context.coordinator.setUpload(upload)
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

/// The terminal's mono font. The base is 13 pt, scaled by the Settings → General → Code size
/// step (`ClaudeTextScale.codeMultiplier()`, the same multiplier `Typography`
/// applies to code text elsewhere), so the terminal follows the user's code-size choice.
enum PaseoTerminalFont {
    static let baseSize: CGFloat = 13

    static func size() -> CGFloat {
        baseSize * ClaudeTextScale.codeMultiplier()
    }

    static func current() -> UIFont {
        UIFont(name: ClaudeFontResources.anthropicMono, size: size())
            ?? UIFont.monospacedSystemFont(ofSize: size(), weight: .regular)
    }
}

/// The user's scrollback preference (Settings → Terminal): how many lines SwiftTerm keeps.
/// `UserDefaults` has no typed integer present when never set — `integer(forKey:)` returns 0,
/// which maps to the 2,000-line default.
enum PaseoTerminalScrollback {
    static let storageKey = "paseo.terminal.scrollback"
    static let defaultValue = 2_000

    static func current(_ defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: storageKey)
        return value > 0 ? value : defaultValue
    }
}

@MainActor
final class PaseoTerminalCoordinator: NSObject, TerminalViewDelegate {
    /// One display frame at 60 Hz: a chunk that arrives inside a frame that already fed bytes
    /// waits for the next tick; a chunk after an idle frame feeds immediately.
    static let frameInterval: CFTimeInterval = 1.0 / 60.0
    /// Activity bookkeeping writes view state at most this often, and never when the tab's dot
    /// would not change.
    static let activityInterval: CFTimeInterval = 0.5
    /// The keyboard and the key bar move the grid in animated steps; the size is sent once they
    /// have settled.
    static let resizeSettle: Duration = .milliseconds(120)
    /// A burst larger than this is fed at once rather than held back for a frame.
    static let maxBufferedBytes = 256 * 1024

    weak var store: TerminalsStore?
    weak var view: TerminalView?
    /// The scrollback the view was last configured with — live re-application on change.
    var appliedScrollback = PaseoTerminalScrollback.defaultValue
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
        guard visible, let store, let terminalId, attachedId == terminalId, let size = attachedSize
        else { return }
        store.resize(terminalId, to: size, intent: .claim)
        claimed = true
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
        pendingBytes.removeAll(keepingCapacity: false)
        lastFeedTime = 0
        lastActivityReport = 0
        if let attachedId { store?.detach(attachedId) }
        attachedId = nil
        attachedSize = nil
        claimed = false
        isAttaching = false
        isReplaying = false
        pendingResize = nil
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
            let stream = await store.attach(terminalId, size: size)
            guard let self else { return }
            self.attachTask = nil
            guard self.terminalId == terminalId else {
                // The user switched terminals while the subscribe was in flight.
                store.detach(terminalId)
                return
            }
            self.attachedId = terminalId
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
        if pendingBytes.isEmpty, now - lastFeedTime >= Self.frameInterval,
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
    fileprivate func flushPending() {
        guard !pendingBytes.isEmpty else {
            flushLink?.isPaused = true
            return
        }
        lastFeedTime = CACurrentMediaTime()
        // `feed` parses synchronously, so the batch buffer is reusable the moment it returns.
        view?.feed(byteArray: pendingBytes[...])
        pendingBytes.removeAll(keepingCapacity: true)
    }

    private func startFlushLink() {
        if let flushLink {
            flushLink.isPaused = false
            return
        }
        let target = PaseoTickTarget()
        target.coordinator = self
        let link = CADisplayLink(target: target, selector: #selector(PaseoTickTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        flushLink = link
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
        // Only the terminal on screen claims the PTY size, and only once; later changes from this
        // attachment are updates. A retained hidden tab never claims.
        let intent: TerminalResizeIntent = isVisible && !claimed ? .claim : .update
        store.resize(terminalId, to: size, intent: intent)
        if intent == .claim { claimed = true }
        attachedSize = size
        pendingResize = nil
    }
}

/// The display link's target. It holds the coordinator weakly, so a link that outlives its view
/// never owns it.
@MainActor
private final class PaseoTickTarget: NSObject {
    weak var coordinator: PaseoTerminalCoordinator?

    @objc func tick(_ link: CADisplayLink) {
        coordinator?.flushPending()
    }
}

/// Where a terminal link wants to go. Parsed from the implicit/explicit link text.
enum TerminalLinkTarget: Equatable {
    /// `path:line[:col]` — absolute, `~/` or workspace-relative. The page opens the file viewer.
    case localFile(path: String, line: Int?, col: Int?)
    /// http/https/mailto/file URLs and anything Safari can take.
    case url(URL)
    /// Nothing we can act on (a raw git SHA, a word, …).
    case unhandled(String)
}

/// Classifies link text from SwiftTerm's implicit detector (and explicit OSC 8 payloads).
/// Paths win when the text contains a slash (or `~`): `Sources/Foo.swift:42` and
/// `/abs/path:42:3` open the viewer; scheme URLs go to Safari.
nonisolated func parseLinkTarget(_ link: String) -> TerminalLinkTarget {
    let lower = link.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://")
        || lower.hasPrefix("mailto:") || lower.hasPrefix("file://") {
        if let url = URL(string: link) { return .url(url) }
        return .unhandled(link)
    }
    if link.contains("://") { return .unhandled(link) }
    guard link.contains("/") || link.hasPrefix("~") else { return .unhandled(link) }

    var segments = link.split(separator: ":").map(String.init)
    var line: Int?
    var col: Int?
    if let last = segments.last, !last.isEmpty, last.allSatisfy(\.isNumber) {
        segments.removeLast()
        if let second = segments.last, !second.isEmpty, second.allSatisfy(\.isNumber) {
            segments.removeLast()
            line = Int(second)
            col = Int(last)
        } else {
            line = Int(last)
        }
    }
    let path = segments.joined(separator: ":")
    guard !path.isEmpty else { return .unhandled(link) }
    return .localFile(path: path, line: line, col: col)
}
#endif
