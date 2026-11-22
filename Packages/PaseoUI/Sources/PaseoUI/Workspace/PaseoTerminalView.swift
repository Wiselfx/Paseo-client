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
        let view: TerminalView = PaseoTerminalSurface(frame: .zero, font: PaseoTerminalFont.current())
        view.terminalDelegate = context.coordinator
        // SwiftUI owns the geometry: the frame already sits inside the safe area and above the
        // keyboard and key bar. The emulator's own automatic inset counted the overlapping safe
        // area a second time, and that inset moved while the keyboard animated, so the last
        // rows jumped and the bottom spacing never settled.
        view.contentInsetAdjustmentBehavior = .never
        let scrollback = PaseoTerminalScrollback.current()
        view.changeScrollback(scrollback)
        context.coordinator.appliedScrollback = scrollback
        // The palette's ink on the panel's canvas, in both schemes, so the terminal always reads
        // as a terminal and the page has no band (E2b §3). Re-resolved on every trait change.
        view.nativeForegroundColor = UIColor(Palette.ink)
        PaseoTerminalBackground.apply(to: view, coordinator: context.coordinator)
        let backgroundTraits: [UITrait] = [UITraitUserInterfaceStyle.self, PureBlackTrait.self]
        view.registerForTraitChanges(backgroundTraits) {
            [weak coordinator = context.coordinator] (view: TerminalView, _: UITraitCollection) in
            guard let coordinator else { return }
            PaseoTerminalBackground.apply(to: view, coordinator: coordinator)
        }
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
        // `makeUIView` builds the view before it inherits the hosting traits; this resolves the
        // panel fill once it is in the hierarchy. Trait changes after that go through the
        // registration in `makeUIView`.
        // Keyed by the scheme, never by comparing `UIColor`s: two equal colours in different
        // colour spaces compare unequal, and re-setting SwiftTerm's background repaints the
        // whole emulator on every update (lead fix at the E2b merge).
        PaseoTerminalBackground.apply(to: uiView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.teardown()
    }
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
