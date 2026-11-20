#if canImport(UIKit)
import SwiftUI

/// The band's own clock: one entry per step while the band moves, one when it comes to rest, and
/// the next cycle's start. Nothing ticks while the band rests (a third of the time), and nothing ticks
/// at the display rate.
struct ClaudeSweepSchedule: TimelineSchedule {
    let start: Date
    var paused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(origin: start.addingTimeInterval(ClaudeMotion.sweepDelay), cursor: startDate, paused: paused)
    }

    struct Entries: Sequence, IteratorProtocol {
        let origin: Date
        var cursor: Date
        let paused: Bool
        var emitted = false

        mutating func next() -> Date? {
            if !emitted {
                emitted = true
                return cursor
            }
            if paused { return nil }
            cursor = Self.boundary(after: cursor, origin: origin)
            return cursor
        }

        static func boundary(after date: Date, origin: Date) -> Date {
            let t = date.timeIntervalSince(origin)
            guard t >= 0 else { return origin }
            let period = ClaudeMotion.statusPeriod
            let active = period * (2.0 / 3.0)
            let step = active / Double(ClaudeMotion.sweepSteps)
            let cycle = (t / period).rounded(.down)
            let inCycle = t - cycle * period
            let next: Double
            if inCycle < active {
                next = cycle * period + Swift.min(((inCycle / step).rounded(.down) + 1) * step, active)
            } else {
                next = (cycle + 1) * period
            }
            return origin.addingTimeInterval(Swift.max(next, t + 0.001))
        }
    }
}
#endif
