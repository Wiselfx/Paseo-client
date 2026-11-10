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

    var animation: Animation {
        switch self {
        case .feedback: .easeOut(duration: 0.12)
        case .fade: .easeOut(duration: 0.2)
        case .disclosure: .smooth(duration: 0.25)
        case .settle: .smooth(duration: 0.32)
        case .glide: .smooth(duration: 0.3)
        case .bubbleEnter: .timingCurve(0.22, 1, 0.36, 1, duration: 0.2)
        }
    }

    /// Under Reduce Motion everything stops except `fade` (opacity is allowed) and `settle`,
    /// which becomes a plain short ease.
    func resolved(reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return animation }
        switch self {
        case .fade: return animation
        case .settle: return .easeOut(duration: 0.2)
        case .feedback, .disclosure, .glide, .bubbleEnter: return nil
        }
    }
}
#endif
