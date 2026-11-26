#if canImport(UIKit)
import UIKit

/// Measurement hooks for the transcript harness (`TranscriptHarnessTests`). Everything here is inert in
/// production: `sink` is nil, so `emit` evaluates nothing, and the two `simulated` flags are false.
///
/// The flags let a test stand in for a finger: a simulated scroll view never has `isDragging` or
/// `isDecelerating` set, and the engine's rules (`isUserScrolling`, the flick rule in
/// `compensatesResize`) read exactly those.
@MainActor
enum TranscriptProbe {
    /// Which rule of `TranscriptEngine.compensatesResize` decided.
    enum Branch: String {
        case pinned, wholeAbove, notStraddling, settlingTurn, tapped, rowAnchor, runningTurn, wholeCell
    }

    enum Event {
        /// A cell's measured height differs from the layout's: `TranscriptLayout.invalidationContext`.
        case invalidation(
            index: Int, id: String, old: CGFloat, new: CGFloat, firstMeasure: Bool, compensated: Bool,
            branch: Branch, frame: CGRect, readerTop: CGFloat)
        /// The engine wrote the content offset itself.
        case offsetWrite(site: String, from: CGFloat, to: CGFloat)
        /// `cellForItemAt`: a cell was dequeued and configured.
        case dequeue(index: Int, id: String, hadMeasured: Bool, height: CGFloat)
    }

    static var sink: (@MainActor (Event) -> Void)?
    static var simulatedDragging = false
    static var simulatedDecelerating = false

    @inline(__always)
    static func emit(_ event: @autoclosure () -> Event) {
        sink?(event())
    }
}
#endif
