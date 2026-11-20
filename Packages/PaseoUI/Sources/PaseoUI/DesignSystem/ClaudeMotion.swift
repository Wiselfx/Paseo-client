#if canImport(UIKit)
import SwiftUI

/// Motion timings from the DSH motion table, in one place.
enum ClaudeMotion {
    /// `--dsh-claude-duration-feedback` / reveal / exit.
    static let feedback: Double = 0.12
    /// `--dsh-claude-duration-move`: the height roll on a disclosure.
    static let move: Double = 0.20
    /// The wording swap: the status line's enter/exit pair (OCU §12.22).
    static let swap: Double = 0.24
    /// `--dsh-claude-duration-open`: the overtime badge.
    static let open: Double = 0.3
    /// `--dsh-claude-period-hold` / status sweep.
    static let statusPeriod: Double = 1.5
    /// `--dsh-claude-duration-host-sweep-delay`: the band waits this long after the words appear.
    static let sweepDelay: Double = 0.3
    /// `--dsh-claude-ease-host-sweep`: `steps(48, end)`.
    static let sweepSteps: Int = 48
    /// `--dsh-claude-period-dot-rotate`: a loader motion stands this long before another takes over.
    static let dotRotate: Double = 10
    /// `--dsh-claude-duration-dot-morph`: the hand-over between two loader motions.
    static let dotMorph: Double = 0.48
    /// `WORD_LOCK_MS`: a wording stands for at least a second.
    static let wordLock: Double = 1.0
    /// 10 s of silence before "No response yet".
    static let overtime: Double = 10
    /// `--dsh-claude-duration-rise`: the home greeting rising into place.
    static let rise: Double = 0.45
    /// `--dsh-claude-duration-stagger`: the second entrance starts this much later.
    static let stagger: Double = 0.07
    /// `--dsh-claude-distance-rise`.
    static let riseDistance: CGFloat = 12
    /// `--dsh-claude-blur-enter`.
    static let enterBlur: CGFloat = 3
}
#endif
