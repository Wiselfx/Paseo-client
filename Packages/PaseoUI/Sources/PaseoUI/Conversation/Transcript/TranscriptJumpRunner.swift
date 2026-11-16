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
        /// The turn's `ForEach` id: always known to the stack, so it is what the first scroll asks for. Read
        /// again every tick: a turn's id is its first row's id, so it changes when an older page prepends
        /// rows to a partial turn while the runner is on its way (a fetched window does exactly that).
        /// Nil while the turn cannot be found.
        var turnId: @MainActor () -> String?
        /// The id to settle on, read again every tick: a streaming row's id moves with every delta.
        /// Nil settles on the turn itself.
        var rowId: @MainActor () -> String?
        /// The row's place in the viewport: the match for a find step, the top for a prompt. Read when
        /// the row is aimed at, so it can use what the layout knows by then (a turn's height).
        var rowAnchor: @MainActor () -> UnitPoint
        /// Whether the row has really arrived, when the transcript can tell (the end marker: the end of
        /// the content is at the bottom; a find row: its measured frame holds the match under the
        /// viewport). The runner aims again, a few times, while this says no.
        var isReached: @MainActor () -> Bool = { true }
        /// The first aim at the row glides (the row is inside the turn just reached). The end marker of a
        /// tall last turn is thousands of points away, so it does not.
        var glides = true
    }

    /// What the runner needs from the transcript.
    struct Hooks {
        /// The lazy stack has built this turn (its `onAppear` ran and its `onDisappear` has not).
        var isMounted: @MainActor (String) -> Bool
        /// Where the turn really is (measured by its own geometry callback, not estimated), and the
        /// viewport's own numbers. Nil until the turn has been measured.
        var probe: @MainActor (String) -> Probe?
        /// Scroll to a view id. The flag asks for a glide; the runner passes false for the long hops.
        var scrollTo: @MainActor (_ id: String, _ anchor: UnitPoint, _ animated: Bool) -> Void
        /// A finger, a flick or a deceleration owns the scroll view: the reader's, which always wins.
        var isScrolling: @MainActor () -> Bool
        /// Moves the offset by a point, which makes the stack look again.
        var nudge: @MainActor () -> Void
        /// Reached: the row is under the viewport. Called once; also when the runner gives up, so the
        /// caller never waits on it.
        var landed: @MainActor () -> Void
    }

    /// A measurement of the target turn against the viewport, in content coordinates.
    struct Probe: Equatable {
        var turnOffset: CGFloat
        var turnHeight: CGFloat
        var contentOffset: CGFloat
        var visibleHeight: CGFloat
        var contentHeight: CGFloat

        /// Some part of the turn is under the viewport.
        var isInView: Bool {
            turnOffset < contentOffset + visibleHeight && turnOffset + turnHeight > contentOffset
        }

        /// What must stay equal between two looks for the layout to count as settled: where the turn
        /// is, how tall everything is and where the viewport sits.
        var layoutKey: [Int] {
            [Int(turnOffset.rounded()), Int(contentHeight.rounded()), Int(contentOffset.rounded())]
        }
    }

    /// A tick every 100 ms, at most 120 of them: a layout that never settles cannot loop (rule 14).
    static let tickInterval: Duration = .milliseconds(100)
    static let maxTicks = 120
    /// Looks at an unchanged layout before it is trusted (the stack measures rows over several frames).
    static let stableLooks = 2
    /// The most times the turn is asked for again, and the row aimed at: a bound, not a goal.
    static let maxTurnAims = 12
    /// Ticks to wait before asking for the turn again while it has not appeared: a state change (the
    /// window growing, a fetched window merging) needs a layout before the id exists, and a cold layout of
    /// tall turns takes several hundred milliseconds.
    static let reaskAfter = 4
    static let maxRowAims = 2
    /// Extra aims allowed while `isReached` says no.
    static let maxReachAims = 6

    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func run(_ target: Target, hooks: Hooks) {
        cancel()
        PaseoPerf.mark("jump.run")
        task = Task { @MainActor in await Self.steps(target, hooks) }
    }

    /// The steps, separated from the task so they read in order.
    ///
    /// Each aim at a far id lands where the stack *estimates* the id to be; the rows it builds there are
    /// measured and the estimate shifts, so one aim can end a few screens off (a cold open of a 65 000 pt
    /// chat did). The stack's estimate improves with every row it measures near the viewport, so aiming
    /// again from where the last aim ended converges. The runner therefore looks at the real, measured
    /// frame of the turn (`probe`) after the scroll has stopped and the layout has held still, and
    /// aims again until the turn is under the viewport; only then does it aim at the row inside it.
    private static func steps(_ target: Target, _ hooks: Hooks) async {
        var turnAims = 0
        var rowAims = 0
        var stable = 0
        var lastKey: [Int] = []
        var lastTurnAimTick = -reaskAfter
        for tick in 0..<maxTicks {
            // Always after a pause: the state change that started the jump (the window, a turn opening
            // for the match) lays out before the first look.
            try? await Task.sleep(for: tickInterval)
            guard !Task.isCancelled else { return }
            if hooks.isScrolling() {
                PaseoPerf.count("jump.wait.scrolling")
                stable = 0
                continue
            }
            guard let turnId = target.turnId() else {
                stable = 0
                continue
            }
            guard hooks.isMounted(turnId), let probe = hooks.probe(turnId) else {
                // Not built, or built and not measured yet: ask for the turn (instant: a long glide is
                // what leaves the stack without rows).
                stable = 0
                guard tick - lastTurnAimTick >= reaskAfter else { continue }
                guard turnAims < maxTurnAims else {
                    PaseoPerf.mark("jump.gaveUp.unmounted")
                    break
                }
                turnAims += 1
                lastTurnAimTick = tick
                PaseoPerf.count("jump.turnAim.unmounted")
                if turnAims > 3 { hooks.nudge() }
                hooks.scrollTo(turnId, .top, false)
                continue
            }
            if probe.layoutKey == lastKey { stable += 1 } else { stable = 0 }
            lastKey = probe.layoutKey
            guard probe.isInView else {
                // Built but off screen (the estimate was off): aim again from here.
                stable = 0
                guard tick - lastTurnAimTick >= reaskAfter else { continue }
                guard turnAims < maxTurnAims else {
                    PaseoPerf.mark("jump.gaveUp.offscreen")
                    break
                }
                turnAims += 1
                lastTurnAimTick = tick
                PaseoPerf.count("jump.turnAim.offscreen")
                if turnAims > 3 { hooks.nudge() }
                hooks.scrollTo(turnId, .top, false)
                continue
            }
            guard stable >= stableLooks else {
                PaseoPerf.count("jump.wait.unstable")
                continue
            }
            // The turn is in view and the layout has held: aim at the row inside it. Twice, the second a
            // no-op unless something above the row finished measuring after the first.
            let row = target.rowId()
            let reached = target.isReached()
            if PaseoPerf.enabled {
                PaseoPerf.countNamed(
                    "jump.tick.aims\(rowAims).reached\(reached).o\(Int(probe.turnOffset)).h\(Int(probe.turnHeight)).co\(Int(probe.contentOffset)).vh\(Int(probe.visibleHeight)).ch\(Int(probe.contentHeight))")
            }
            if rowAims < maxRowAims || (!reached && rowAims < maxRowAims + maxReachAims) {
                rowAims += 1
                PaseoPerf.count("jump.rowAim")
                stable = 0
                hooks.scrollTo(row ?? turnId, row == nil ? .top : target.rowAnchor(), target.glides && rowAims == 1)
                continue
            }
            PaseoPerf.mark("jump.landed")
            hooks.landed()
            return
        }
        PaseoPerf.mark("jump.gaveUp")
        hooks.landed()
    }
}
#endif
