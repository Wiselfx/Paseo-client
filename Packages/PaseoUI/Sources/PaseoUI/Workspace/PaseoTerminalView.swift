#if canImport(UIKit)
import PaseoStore
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
    /// Called when the daemon detaches the stream. A non-nil error means observation failed and
    /// the process may still be running; nil means it ended cleanly.
    var onExit: (String?) -> Void = { _ in }
    /// Called on every live output chunk, for activity tracking in the tab strip.
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
        // The virtual key bar replaces SwiftTerm's built-in one: our keys, our haptics.
        view.inputAccessoryView = context.coordinator.makeKeyBar(for: view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.configure(
            store: store, onOutput: onOutput, onOpenLink: onOpenLink, onExit: onExit,
            onAttach: onAttach, onCancelUpload: onCancelUpload)
        context.coordinator.select(terminalId: terminalId)
        context.coordinator.setUpload(upload)
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

/// The terminal's mono font. The base is 13 pt, scaled by the Settings → General → Code size
/// step (`ClaudeTextScale.codeMultiplier()`, the same multiplier `ClaudeTypography.mono`
/// applies to code text elsewhere), so the terminal follows the user's code-size choice.
enum PaseoTerminalFont {
    static let baseSize: CGFloat = 13

    static func size() -> CGFloat {
        baseSize * ClaudeTextScale.codeMultiplier()
    }

    static func current() -> UIFont {
        UIFont(name: ClaudeTypography.anthropicMono, size: size())
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
    weak var store: TerminalsStore?
    weak var view: TerminalView?
    /// The scrollback the view was last configured with — live re-application on change.
    var appliedScrollback = PaseoTerminalScrollback.defaultValue
    /// The font size the view was last configured with — live re-application on a Code size
    /// change, without touching the emulator buffer (scrollback survives).
    var appliedFontSize = PaseoTerminalFont.baseSize

    private var terminalId: String?
    private var lastSize: TerminalSize?
    private var attachedId: String?
    private var attachedSize: TerminalSize?
    private var didClaim = false
    private var isAttaching = false
    private var isReplaying = false
    private var pendingResize: TerminalSize?
    private var attachTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
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

    /// Releases the subscription, cancels the byte pump and resets the emulator.
    func teardown() {
        attachTask?.cancel()
        attachTask = nil
        streamTask?.cancel()
        streamTask = nil
        if let attachedId { store?.detach(attachedId) }
        attachedId = nil
        attachedSize = nil
        didClaim = false
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
            if attachedSize != size { sendResize(size) }
            return
        }
        if isAttaching {
            pendingResize = size
            return
        }
        isAttaching = true
        attachTask = Task { [weak self] in
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
            // Attaching claims the PTY size; later geometry changes travel as `update`.
            store.resize(terminalId, to: size, intent: .claim)
            self.didClaim = true
            if let pending = self.pendingResize, pending != size {
                store.resize(terminalId, to: pending, intent: .update)
                self.attachedSize = pending
            }
            self.pendingResize = nil
            self.consume(stream, for: terminalId)
        }
    }

    private func consume(_ stream: AsyncStream<TerminalOutput>, for terminalId: String) {
        streamTask = Task { [weak self] in
            for await output in stream {
                guard let self else { return }
                guard self.attachedId == terminalId else { break }
                switch output {
                case .replayBegin:
                    self.isReplaying = true
                    self.view?.resetToInitialState()
                case .output(let data):
                    self.onOutput()
                    self.view?.feed(byteArray: ArraySlice([UInt8](data)))
                case .replayEnd:
                    self.isReplaying = false
                case .exited(let error):
                    self.isReplaying = false
                    self.onExit(error)
                }
            }
        }
    }

    private func sendResize(_ size: TerminalSize) {
        guard let store, let terminalId else { return }
        let intent: TerminalResizeIntent = didClaim ? .update : .claim
        store.resize(terminalId, to: size, intent: intent)
        attachedSize = size
        didClaim = true
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
