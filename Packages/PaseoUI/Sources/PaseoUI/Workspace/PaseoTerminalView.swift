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
/// `nativeForegroundColor`/`nativeBackgroundColor`, `terminalDimensions` (not used; the
/// delegate's `sizeChanged` reports the grid), and the `TerminalViewDelegate` protocol
/// (`sizeChanged`, `setTerminalTitle`, `hostCurrentDirectoryUpdate`, `send`, `scrolled`,
/// `rangeChanged`; the rest have defaults).
struct PaseoTerminalView: UIViewRepresentable {
    typealias UIViewType = TerminalView
    typealias Coordinator = PaseoTerminalCoordinator

    let store: TerminalsStore
    let terminalId: String?
    /// Called when the daemon detaches the stream. A non-nil error means observation failed and
    /// the process may still be running; nil means it ended cleanly.
    var onExit: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalView {
        ClaudeFontResources.register()
        let font =
            UIFont(name: ClaudeTypography.anthropicMono, size: 13)
            ?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let view = TerminalView(frame: .zero, font: font)
        view.terminalDelegate = context.coordinator
        // ClaudePalette's #141413 in dark mode; used in light mode too so the terminal always
        // reads as a terminal.
        view.nativeForegroundColor = UIColor(red: 0.949, green: 0.937, blue: 0.914, alpha: 1)
        view.nativeBackgroundColor = UIColor(red: 20 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.configure(store: store, onExit: onExit)
        context.coordinator.select(terminalId: terminalId)
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

@MainActor
final class PaseoTerminalCoordinator: NSObject, TerminalViewDelegate {
    weak var store: TerminalsStore?
    weak var view: TerminalView?

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
    private var onExit: (String?) -> Void = { _ in }

    func configure(store: TerminalsStore, onExit: @escaping (String?) -> Void) {
        self.store = store
        self.onExit = onExit
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
#endif
