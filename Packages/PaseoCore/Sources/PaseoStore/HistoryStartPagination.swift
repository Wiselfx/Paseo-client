import Foundation

// Pure model of the "load older history when the reader reaches the start" operation.
//
// Upstream: packages/app/src/agent-stream/history-start-pagination.ts (`createHistoryStartPagination`).
// The transitions mirror it 1:1. What differs is only how the controller is driven:
// - No timers. The caller injects `now` into `update(_:now:)`, so the 15 s watchdog is evaluated when
//   the caller calls `update`. A caller that wants the watchdog to fire while nothing else changes must
//   call `update` on its own clock.
// - No scheduler. Upstream calls `scheduleSettle()` and then `settle()` on a frame loop; the caller owns
//   that loop (`history-start-settle-scheduler.ts`, not ported).
// - `update` returns whether the caller must start one fetch. Upstream starts it inside `update` through
//   `load()`.
// - `settle` and `rearm` return `Void`. Upstream calls `update()` at the end of some branches. Here the
//   caller calls `update(_:now:)` after them to get that decision.

/// Upstream `HistoryStartPaginationState["status"]` (history-start-pagination.ts:1-5, :10-11).
public enum HistoryStartPaginationStatus: String, Sendable, Equatable {
    case dormant, ready, loading, settling, failed
}

/// Upstream `HistoryStartPaginationState` (history-start-pagination.ts:10-13).
public struct HistoryStartPaginationState: Sendable, Equatable {
    public var status: HistoryStartPaginationStatus
    public var visible: Bool

    public init(status: HistoryStartPaginationStatus, visible: Bool) {
        self.status = status
        self.visible = visible
    }
}

/// Upstream `HistoryStartPaginationInput` (history-start-pagination.ts:3-9), plus the derived geometry.
public struct HistoryStartGeometry: Sendable, Equatable {
    public var distanceFromHistoryStart: Double
    public var isUnderfilled: Bool
    public var hasOlderHistory: Bool
    public var isLoadingOlderHistory: Bool
    public var isReady: Bool
    /// Identity of the oldest loaded history. Nil when there is none to key on.
    public var progressKey: String?
}

/// The geometry formula of upstream `nativeHistoryStartGeometry` (native-history-start-geometry.ts:1-13).
public enum HistoryStartGeometryProvider {
    /// Upstream `nativeHistoryStartGeometry` (native-history-start-geometry.ts:4-12). The `32` is the
    /// same constant as upstream, and so is the `topOverlayInset` term.
    public static func geometry(
        contentHeight: Double,
        viewportHeight: Double,
        offsetY: Double,
        topOverlayInset: Double,
        hasOlderHistory: Bool,
        isLoadingOlderHistory: Bool,
        isReady: Bool,
        progressKey: String?
    ) -> HistoryStartGeometry {
        // Upstream native-history-start-geometry.ts:9-10.
        let contentExtent = contentHeight - 32 - topOverlayInset
        return HistoryStartGeometry(
            // Upstream native-history-start-geometry.ts:11.
            distanceFromHistoryStart: max(0, offsetY - topOverlayInset - 32),
            // Upstream native-history-start-geometry.ts:12.
            isUnderfilled: contentExtent < viewportHeight,
            hasOlderHistory: hasOlderHistory,
            isLoadingOlderHistory: isLoadingOlderHistory,
            isReady: isReady,
            progressKey: progressKey
        )
    }
}

/// One history-start pagination operation, as a value. Feed it geometry with `update(_:now:)`; it says
/// when to start a fetch. Report the fetch with `loadCompleted(applied:)`, then call `update` again.
///
/// The watchdog and the settle decision use the caller's clock and geometry, so the model is
/// deterministic and testable.
public struct HistoryStartPagination: Sendable {
    /// Upstream `HISTORY_START_THRESHOLD_PX` (history-start-pagination.ts:1).
    private static let thresholdPx: Double = 96
    /// Upstream watchdog `setTimeout(..., 15_000)` (history-start-pagination.ts:63).
    private static let watchdogSeconds: TimeInterval = 15

    public private(set) var state: HistoryStartPaginationState
    /// Upstream `requestedKey` (history-start-pagination.ts:31).
    private var requestedKey: String?
    /// Upstream `completed` (history-start-pagination.ts:31): the fetch of the current request finished.
    private var completed = false
    /// Upstream `fill` (history-start-pagination.ts:32): the request was started because the list was
    /// underfilled, so settling waits for it to fill.
    private var fill = false
    /// When the watchdog timer was armed: the request time, or the first ready observation after a
    /// completed request was reset. Nil when no timer is armed (upstream `timeout === undefined`).
    private var watchStartedAt: Date?

    public init(initiallyVisible: Bool) {
        state = HistoryStartPaginationState(status: .dormant, visible: initiallyVisible)
    }

    /// Mirrors upstream createHistoryStartPagination.update(). Returns true EXACTLY ONCE per request:
    /// true on the call that transitions into .loading (the caller must then start one fetch).
    public mutating func update(_ geometry: HistoryStartGeometry?, now: Date = Date()) -> Bool {
        // Upstream watchProgress runs before the `!geometry` return (history-start-pagination.ts:68-69).
        if isLoadingOperation, runWatchdog(geometry, now: now) == false {
            return false
        }
        guard let geometry else { return false }

        if state.status == .loading {
            // Upstream :72. A completed request is only waiting for the progress key to change or for
            // the history to run out.
            guard completed else { return false }
            if let progressKey = geometry.progressKey, progressKey != requestedKey {
                // Upstream :74-75: the next step is the settle, which the caller schedules.
                publish(.settling)
            } else if !geometry.hasOlderHistory {
                // Upstream :76-77: nothing older to load.
                finish(.dormant)
            }
            return false
        }

        // Upstream :81. A failed or settling operation waits. So does a view that is not ready yet.
        if state.status == .settling || state.status == .failed || !geometry.isReady {
            return false
        }
        let atStart = geometry.distanceFromHistoryStart <= Self.thresholdPx
        if state.status == .dormant, !geometry.isUnderfilled {
            // Upstream :83-85: a list that fills the viewport stays dormant, and is shown.
            publish(.dormant, visible: true)
            return false
        }
        // Upstream :87: a request needs the reader at the start. A list that is not underfilled also
        // needs `.ready` (a dormant list is re-armed by a user scroll first).
        if !atStart || (!geometry.isUnderfilled && state.status != .ready) {
            return false
        }
        if !geometry.hasOlderHistory {
            // Upstream :88-90.
            finish(.dormant)
            return false
        }
        // Upstream :92: a request in flight, or nothing to key progress on, suppresses the next one.
        if geometry.isLoadingOlderHistory || geometry.progressKey == nil {
            return false
        }

        // Upstream :93-96: start the request.
        fill = geometry.isUnderfilled
        requestedKey = geometry.progressKey
        completed = false
        publish(.loading)
        watchStartedAt = now
        return true
    }

    /// The fetch finished. applied == false -> .failed. Sets `completed`; the next update() call then
    /// observes it (it does NOT change state by itself).
    ///
    /// A completion that arrives when no request is in flight (the watchdog failed it, say) is ignored,
    /// as upstream ignores a stale `generation` (history-start-pagination.ts:100-101, :111).
    public mutating func loadCompleted(applied: Bool) {
        guard state.status == .loading, !completed else { return }
        completed = true
        if !applied {
            finish(.failed)
        }
    }

    /// Mirrors upstream settle(): .settling -> .ready (distance > 96) / .dormant (underfilled filled or
    /// !hasOlderHistory). No-op otherwise.
    ///
    /// The still-underfilled branch (upstream history-start-pagination.ts:131-133) leaves `.ready`, and
    /// the caller then calls `update(_:now:)`, which starts the next request if one is due.
    public mutating func settle(_ geometry: HistoryStartGeometry?) {
        // Upstream :121-124.
        guard state.status == .settling, let geometry, geometry.isReady else { return }
        clearWatchdog()
        if fill, !geometry.isUnderfilled {
            // Upstream :125-126.
            publish(.dormant, visible: true)
        } else if geometry.distanceFromHistoryStart > Self.thresholdPx {
            // Upstream :127-128: the reader has moved away from the start.
            publish(.ready, visible: true)
        } else if !geometry.hasOlderHistory {
            // Upstream :129-130.
            publish(.dormant, visible: true)
        } else {
            // Upstream :131-133 (publish "ready", then update()).
            publish(.ready)
        }
    }

    /// Mirrors upstream rearm(): .failed -> .ready (and .ready re-arms from there). Also used by the retry button.
    ///
    /// Upstream also re-arms `.dormant` (history-start-pagination.ts:137), and the native strategy does
    /// that on the first user drag (strategy-native.tsx:571). Without it a dormant list never requests at
    /// the start. Upstream calls `update()` after it. The caller calls `update(_:now:)` instead.
    public mutating func rearm() {
        if state.status == .dormant || state.status == .failed {
            publish(.ready, visible: true)
        }
    }

    // MARK: - Internals

    private var isLoadingOperation: Bool {
        state.status == .loading || state.status == .settling
    }

    /// Mirrors upstream `watchProgress` (history-start-pagination.ts:52-65) with the 15 s timer as a
    /// deadline. Returns `false` when the watchdog failed the operation.
    private mutating func runWatchdog(_ geometry: HistoryStartGeometry?, now: Date) -> Bool {
        // Upstream :53-55: a completed request waits for its view to be measurable again. The timer
        // is cleared, and it is armed again when the view is ready.
        if completed, geometry?.isReady != true {
            clearWatchdog()
            return true
        }
        guard let started = watchStartedAt else {
            // Upstream :56-57: arm the timer.
            watchStartedAt = now
            return true
        }
        // Upstream :58-63: the timer fires. A request that never completed fails (:62).
        if now.timeIntervalSince(started) > Self.watchdogSeconds {
            finish(.failed)
            return false
        }
        return true
    }

    /// Upstream `clear()` (history-start-pagination.ts:41-44): cancels the watchdog.
    private mutating func clearWatchdog() {
        if watchStartedAt != nil { watchStartedAt = nil }
    }

    /// Upstream `finish` (history-start-pagination.ts:45-48): clears the watchdog and publishes with
    /// `visible = true`.
    private mutating func finish(_ status: HistoryStartPaginationStatus) {
        clearWatchdog()
        publish(status, visible: true)
    }

    /// Upstream `publish` (history-start-pagination.ts:24-29): writes only on change.
    private mutating func publish(_ status: HistoryStartPaginationStatus, visible: Bool? = nil) {
        let nextVisible = visible ?? state.visible
        if status == state.status, nextVisible == state.visible { return }
        state = HistoryStartPaginationState(status: status, visible: nextVisible)
    }
}
