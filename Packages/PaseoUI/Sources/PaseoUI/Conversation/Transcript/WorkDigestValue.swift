#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// What the digest reads off its run.
struct WorkDigestValue {
    var thoughts: [TimelineRow] = []
    var thoughtSeconds: TimeInterval?
    /// The run's newest row is a thought: it is being thought right now if the run is live.
    var endsInThought = false
    var steps: [WorkRow] = []
    var failures = 0
    var summary = ""
    /// The newest call still running, worded.
    var running: WorkToolWording?
}
#endif
