#if canImport(UIKit)
import Synchronization

/// Marks a queued offscreen render as no longer wanted. `RichSnapshotQueue` flips it from the
/// requester's cancellation handler (any thread) and reads it on the main actor when the job's
/// turn comes, so a card that scrolled away before its render started costs nothing. A render
/// that already started is left to finish: interrupting it would cut the layout settle short and
/// leave the shared web view mid-load for the next job.
final class RenderTicket: Sendable {
    private let cancelled = Mutex(false)

    var isCancelled: Bool { cancelled.withLock { $0 } }

    func cancel() {
        cancelled.withLock { $0 = true }
    }
}
#endif
