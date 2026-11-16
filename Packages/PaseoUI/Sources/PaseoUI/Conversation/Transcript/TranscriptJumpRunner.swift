#if canImport(UIKit)
import SwiftUI

/// Gets the transcript to a row that may be thousands of points away, in a lazy stack, and makes sure
/// it arrives with rows under it (find in chat, the outline rail, a media item, closing find).
///
/// Why a runner: a row's id lives inside its turn, and the lazy stack only knows an id inside a turn
/// it has built. Asking for `row:<seq>` of a turn that was never realised does nothing (find did not
/// move at all), and one big offset jump (`scrollTo(y:)`, an edge) leaves the stack without rows until
/// a real scroll (the blank screen of `W1-findings.md`, rules 12 and 15). What does work is scrolling
/// to a *real id* (`ScrollPosition.scrollTo(id:)` positions a realised row and does not fight the
/// estimated height): to the turn first (its `ForEach` id is known without building it), and, once the
/// stack has built that turn, to the row inside it. The runner does those steps in order and checks
/// the screen after each, one tick at a time (`tick`), so each step runs on a settled layout.
///
/// It owns no scroll handle: the transcript passes closures, so the stack, the track and the position
/// stay where they are (R-3, one owner per gesture surface).
@MainActor final class TranscriptJumpRunner {
    /// Where to go.
    struct Target {
        /// The turn's `ForEach` id: always known to the stack, so it is what the first scroll asks for.
        var turnId: String
        /// The id to settle on, read again every tick: a streaming row's id moves with every delta.
        /// Nil settles on the turn itself.
        var rowId: @MainActor () -> String?
        /// The row's place in the viewport: centre for a find step, top for a prompt.
        var rowAnchor: UnitPoint
    }

    /// What the runner needs from the transcript.
    struct Hooks {
        /// The lazy stack has built this turn (its `onAppear` ran and its `onDisappear` has not).
        var isMounted: @MainActor (String) -> Bool
        /// Scroll to a view id. The flag asks for a glide; the runner passes false for the long hop.
        var scrollTo: @MainActor (_ id: String, _ anchor: UnitPoint, _ animated: Bool) -> Void
        /// A finger, a flick, a deceleration or a programmatic animation owns the scroll view.
        var isScrolling: @MainActor () -> Bool
        /// Mounted turns exist but none is under the viewport (the blank stack).
        var isBlank: @MainActor () -> Bool
        /// Moves the offset by a point, which makes the stack look again.
        var nudge: @MainActor () -> Void
        /// Reached: the row is under the viewport. Called once; also when the runner gives up, so the
        /// caller never waits on it.
        var landed: @MainActor () -> Void
    }

    /// A tick every 100 ms, at most 50 of them: a layout that never settles cannot loop (rule 14).
    static let tickInterval: Duration = .milliseconds(100)
    static let maxTicks = 50
    /// Ticks to wait before asking for the turn again (the window growth or the jump needs a layout).
    static let reissueAfter = 4
    /// Ticks the row's own scroll needs before the screen is judged.
    static let settleTicks = 3

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(_ target: Target, hooks: Hooks) {
        cancel()
        task = Task { @MainActor in await Self.steps(target, hooks) }
    }

    /// The steps, separated from the task so they read in order.
    private static func steps(_ target: Target, _ hooks: Hooks) async {
        var turnAskedAt: Int?
        var finalAskedAt: Int?
        var reissues = 0
        var aims = 0
        for tick in 0..<maxTicks {
            // Always after a pause: the state change that started the jump (the window, a turn opening
            // for the match) lays out before the first look.
            try? await Task.sleep(for: tickInterval)
            guard !Task.isCancelled else { return }
            let mounted = hooks.isMounted(target.turnId)
            guard mounted else {
                // Not built yet: ask for the turn (instant: a long glide is what leaves the stack
                // without rows), and again when a few ticks have passed without it appearing.
                if turnAskedAt == nil || tick - (turnAskedAt ?? tick) >= reissueAfter {
                    if turnAskedAt != nil {
                        reissues += 1
                        if reissues > 3 { hooks.nudge() }
                    }
                    turnAskedAt = tick
                    finalAskedAt = nil
                    hooks.scrollTo(target.turnId, .top, false)
                }
                continue
            }
            let row = target.rowId()
            let finalId = row ?? target.turnId
            let anchor = row == nil ? UnitPoint.top : target.rowAnchor
            guard let askedAt = finalAskedAt else {
                finalAskedAt = tick
                aims = 1
                // Near (the turn was mounted when this began) glides; after a long hop the row is
                // inside the turn just reached, so the last stretch is short and glides too.
                hooks.scrollTo(finalId, anchor, true)
                continue
            }
            if hooks.isScrolling() { continue }
            if tick - askedAt < settleTicks { continue }
            if hooks.isBlank() {
                reissues += 1
                guard reissues <= 6 else { break }
                hooks.nudge()
                finalAskedAt = tick
                hooks.scrollTo(finalId, anchor, false)
                continue
            }
            // Aim once more: a turn that opened or closed for the match, a row that finished measuring,
            // moves the row after the first scroll was made. A no-op when nothing moved.
            if aims < 2 {
                aims += 1
                finalAskedAt = tick
                hooks.scrollTo(finalId, anchor, false)
                continue
            }
            hooks.landed()
            return
        }
        hooks.landed()
    }
}
#endif
