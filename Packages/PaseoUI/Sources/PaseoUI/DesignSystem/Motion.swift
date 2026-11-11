#if canImport(UIKit)
import SwiftUI

/// The only UI motion curves. Continuous loops (spinners, sweeps, `TimelineView`) keep their
/// `linear` animations; the DSH timings stay in `ClaudeMotion`.
enum Motion: CaseIterable {
    /// Press states, symbol swaps.
    case feedback
    /// Opacity and insert/remove transitions.
    case fade
    /// Expand/collapse, size and layout changes.
    case disclosure
    /// Surfaces settling.
    case settle
    /// Programmatic scrolls.
    case glide
    /// The user bubble's entrance.
    case bubbleEnter
    /// The status line's wording swap (OCU §12.22).
    case swap
    /// The transcript header leaving and returning (H2 §3): interruptible, so a reversal
    /// retargets from wherever the bar is.
    case header

    var animation: Animation {
        switch self {
        // OCU official ease-out, `cubic-bezier(.165,.84,.44,1)`, at snap 120 / base 200 ms.
        // Surfaces stay critically damped springs (UX-SPEC §0.4): no OCU overshoot.
        case .feedback: Motion.ocuOut(0.12)
        case .fade: Motion.ocuOut(0.2)
        case .disclosure: .smooth(duration: 0.25)
        case .settle: .smooth(duration: 0.32)
        case .glide: .smooth(duration: 0.3)
        case .bubbleEnter: Motion.ocuOut(0.2)
        case .swap: Motion.ocuOut(0.24)
        case .header: .smooth(duration: 0.26)
        }
    }

    /// OCU's official ease-out curve (`06:366`).
    private static func ocuOut(_ duration: Double) -> Animation {
        .timingCurve(0.165, 0.84, 0.44, 1, duration: duration)
    }

    /// Under Reduce Motion everything stops except `fade` (opacity is allowed) and `settle`,
    /// which becomes a plain short ease.
    func resolved(reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return animation }
        switch self {
        case .fade: return animation
        case .settle: return .easeOut(duration: 0.2)
        case .feedback, .disclosure, .glide, .bubbleEnter, .swap, .header: return nil
        }
    }
}
#endif
