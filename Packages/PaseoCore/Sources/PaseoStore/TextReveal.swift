import Foundation

/// Paced reveal for streaming assistant text.
///
/// The pure policy behind the paced reveal, ported from upstream
/// `packages/app/src/agent-stream/text-reveal.ts`.
///
/// Deltas arrive lumpy: the daemon coalesces one message per ~60 ms window, carrying
/// however many characters the model happened to produce in that window. Painting each
/// delta as it lands makes the size of those lumps visible, which is what reads as
/// jagged. So arrival changes the *target* and the reveal rate is derived from the
/// backlog instead — a burst makes the text catch up faster, it doesn't make it jump.
///
/// Rules, all from upstream:
/// - The store keeps the full text. Only the rendered slice is paced, so copy,
///   selection, the chat outline and scroll geometry stay consistent with the screen.
/// - Commits are capped at one per 60 Hz frame, even on high-refresh displays.
/// - First sight of a text is revealed whole; only growth is paced.
/// - The turn's end releases everything; nothing may be held back.
/// - A frame's elapsed time is clamped, so a long stall never produces a wild step.
///
/// Units are UTF-16 code units throughout: `String.utf16` is random-access, so
/// indexing the cut is O(1) in message length. The visible cut is snapped down to a
/// grapheme-cluster boundary. A Swift `String` cannot hold half a surrogate, so the
/// only transient fragments a paced reveal can paint are a trailing joiner or an odd
/// trailing regional indicator — held back while streaming, painted when the turn ends.
public struct TextRevealState: Sendable, Equatable {
    /// The full text as the store knows it.
    public var target: String
    /// UTF-16 units released. Monotonic within a message.
    public var revealed: Int

    public init(target: String, revealed: Int) {
        self.target = target
        self.revealed = revealed
    }
}

/// One paced frame: how much time the reveal may spend, and where the frame clock stands.
public struct TextRevealFrame: Sendable, Equatable {
    public var elapsedMs: Double
    public var frameAtMs: Double

    public init(elapsedMs: Double, frameAtMs: Double) {
        self.elapsedMs = elapsedMs
        self.frameAtMs = frameAtMs
    }
}

public enum TextReveal {
    /// Backlog drains over this horizon. Shorter feels more like the raw arrival pattern;
    /// longer adds lag the user can notice at the end of a turn.
    /// Upstream: `TEXT_REVEAL_HORIZON_MS`.
    public static let horizonMs: Double = 150
    /// Reveal at most once per 60 Hz frame, even on high-refresh displays.
    /// Upstream: `TEXT_REVEAL_FRAME_INTERVAL_MS`.
    public static let frameIntervalMs: Double = 1000 / 60
    /// A frame's elapsed time is clamped to this before use, so a long stall
    /// (backgrounded app, blocked main thread) doesn't produce a wild step.
    private static let maxElapsedMs: Double = 250

    /// Zero-width joiner: a trailing one is waiting on the rest of its sequence.
    private static let joinerValue: UInt32 = 0x200D
    private static let regionalIndicatorLo: UInt32 = 0x1F1E6
    private static let regionalIndicatorHi: UInt32 = 0x1F1FF

    // MARK: - Step

    /// UTF-16 units to release on this frame. Proportional to the backlog, so the reveal
    /// accelerates when the model runs ahead and settles when it doesn't, with a
    /// one-unit floor so the tail always finishes. Never overshoots.
    /// Upstream: `computeRevealStep`.
    public static func computeRevealStep(
        backlog: Int, elapsedMs: Double, horizonMs: Double = horizonMs
    ) -> Int {
        guard backlog > 0 else { return 0 }
        guard horizonMs > 0 else { return backlog }
        let elapsed = min(max(elapsedMs, 0), maxElapsedMs)
        guard elapsed > 0 else { return 0 }
        guard elapsed < horizonMs else { return backlog }
        let step = Int((Double(backlog) * elapsed / horizonMs).rounded(.up))
        return min(backlog, max(1, step))
    }

    /// Pull a cut index back to somewhere it is safe to slice.
    ///
    /// A raw cut at an arbitrary UTF-16 offset can split a grapheme cluster, which makes
    /// one visible glyph briefly render as separate parts while the text streams. The cut
    /// moves down to the enclosing cluster's start; the reveal counter stays monotonic, so
    /// a long cluster can never stall the reveal — the next frame steps past it.
    /// Upstream: `clampToSafeRevealBoundary`.
    public static func clampToSafeRevealBoundary(_ text: String, _ units: Int) -> Int {
        let count = text.utf16.count
        guard units > 0 else { return 0 }
        guard units < count else { return count }
        var index = text.utf16.index(text.utf16.startIndex, offsetBy: units)
        while index > text.utf16.startIndex, String.Index(index, within: text) == nil {
            index = text.utf16.index(before: index)
        }
        return text.utf16.distance(from: text.utf16.startIndex, to: index)
    }

    // MARK: - Frame clock

    /// Keep reveal commits at 60 Hz while carrying timing remainder forward, so a
    /// high-refresh display does not make the reveal render at hardware frame rate.
    /// Nil when the frame is too soon: nothing is released on it.
    /// Upstream: `nextTextRevealFrame`.
    public static func nextFrame(
        previousFrameAtMs: Double?, timestampMs: Double
    ) -> TextRevealFrame? {
        let elapsedMs: Double
        if let previous = previousFrameAtMs {
            elapsedMs = timestampMs - previous
        } else {
            elapsedMs = frameIntervalMs
        }
        guard elapsedMs >= frameIntervalMs else { return nil }
        return TextRevealFrame(
            elapsedMs: elapsedMs,
            frameAtMs: timestampMs - elapsedMs.truncatingRemainder(dividingBy: frameIntervalMs))
    }

    // MARK: - State

    /// First sight of a text is revealed whole. History hydration, timeline replay, a
    /// row remounting on scroll and an already-finished message all render complete on
    /// first paint, without a special case for each.
    /// Upstream: `beginTextReveal`.
    public static func begin(_ text: String) -> TextRevealState {
        TextRevealState(target: text, revealed: text.utf16.count)
    }

    /// Point the reveal at newly arrived text without changing how much is shown.
    /// A shorter string means this slot is showing a different message than the one
    /// the reveal position belongs to.
    /// Upstream: `retargetTextReveal`.
    public static func retarget(_ state: TextRevealState, _ text: String) -> TextRevealState {
        guard state.target != text else { return state }
        return TextRevealState(target: text, revealed: min(state.revealed, text.utf16.count))
    }

    /// Release one frame's worth of units.
    /// Upstream: `advanceTextReveal`.
    public static func advance(
        _ state: TextRevealState, elapsedMs: Double, horizonMs: Double = horizonMs
    ) -> TextRevealState {
        let step = computeRevealStep(
            backlog: state.target.utf16.count - state.revealed,
            elapsedMs: elapsedMs, horizonMs: horizonMs)
        guard step > 0 else { return state }
        return TextRevealState(
            target: state.target, revealed: min(state.target.utf16.count, state.revealed + step))
    }

    /// Release everything, for when the turn ends and nothing may be held back.
    /// Upstream: `completeTextReveal`.
    public static func complete(_ state: TextRevealState) -> TextRevealState {
        guard state.revealed < state.target.utf16.count else { return state }
        return TextRevealState(target: state.target, revealed: state.target.utf16.count)
    }

    public static func isSettled(_ state: TextRevealState) -> Bool {
        state.revealed >= state.target.utf16.count
    }

    // MARK: - Visible text

    /// What should actually be painted this frame.
    ///
    /// `streaming` says whether more text is still expected. While it is, a trailing
    /// fragment waits for the rest of its cluster; once the turn ends everything
    /// received is painted, because nothing more is coming.
    /// Upstream: `visibleRevealedText`.
    public static func visibleText(_ state: TextRevealState, streaming: Bool) -> String {
        if state.revealed >= state.target.utf16.count {
            return streaming ? trimIncompleteTrailingCluster(state.target) : state.target
        }
        let cut = clampToSafeRevealBoundary(state.target, state.revealed)
        guard cut < state.target.utf16.count else { return state.target }
        let index = state.target.utf16.index(state.target.utf16.startIndex, offsetBy: cut)
        guard let stringIndex = String.Index(index, within: state.target) else { return "" }
        return String(state.target[..<stringIndex])
    }

    /// The streaming-only trim without a frame clock: holds back a trailing fragment
    /// that cannot stand on its own (a dangling joiner, an odd regional indicator).
    /// Identity for anything else — including the empty and ASCII cases — so settled
    /// text never takes this path twice.
    public static func trimmedForStreaming(_ text: String) -> String {
        trimIncompleteTrailingCluster(text)
    }

    /// Hold back a trailing fragment that cannot stand on its own.
    ///
    /// The daemon's coalescing window ends a delta wherever the window closes, so a
    /// caught-up reveal can be handed half a flag and paint it. Only fragments that are
    /// certainly waiting on more input are withheld: a trailing joiner, or an odd
    /// regional indicator. A Swift `String` cannot hold a dangling surrogate.
    /// Upstream: `trimIncompleteTrailingCluster`.
    private static func trimIncompleteTrailingCluster(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.last else { return text }
        let dropUnits: Int
        if last.value == joinerValue {
            // A BMP joiner is one UTF-16 unit.
            dropUnits = 1
        } else if isRegionalIndicator(last.value) {
            guard trailingRegionalIndicatorCount(scalars) % 2 == 1 else { return text }
            // A regional indicator is supplementary: two UTF-16 units.
            dropUnits = 2
        } else {
            return text
        }
        let whole = text.utf16.count
        let cut = clampToSafeRevealBoundary(text, whole - dropUnits)
        guard cut == whole - dropUnits else {
            // The fragment merged with the cluster before it (Swift segments a trailing
            // joiner with its base), so it cannot be split off: paint through. The fragment
            // itself is invisible, and the next delta steps past it.
            return text
        }
        guard cut < whole else { return text }
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: cut)
        guard let stringIndex = String.Index(index, within: text) else { return text }
        return String(text[..<stringIndex])
    }

    private static func isRegionalIndicator(_ value: UInt32) -> Bool {
        value >= regionalIndicatorLo && value <= regionalIndicatorHi
    }

    /// Code points in the trailing regional-indicator run. A flag is a pair.
    private static func trailingRegionalIndicatorCount(
        _ scalars: String.UnicodeScalarView
    ) -> Int {
        var count = 0
        var index = scalars.endIndex
        while index > scalars.startIndex {
            let previous = scalars.index(before: index)
            guard isRegionalIndicator(scalars[previous].value) else { break }
            count += 1
            index = previous
        }
        return count
    }
}
