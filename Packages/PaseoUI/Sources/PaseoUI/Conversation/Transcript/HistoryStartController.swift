import Observation
import PaseoStore

/// Drives older-history loading from the Core's pagination state machine (`HistoryStartPagination`,
/// PaseoStore). Upstream: `packages/app/src/agent-stream/use-history-start-pagination.ts:9` (hook) and
/// `history-start-pagination.ts:22` (the machine; threshold at line 1).
///
/// This is an adapter and nothing more. The machine decides when a page is wanted, retried or
/// settled; this class builds its geometry from the transcript's scroll numbers and the store, and
/// publishes `state` only when the machine's state changes (never per scroll frame).
///
/// Not built or run on this host (PaseoUI is Apple-only); written against the Core contract as
/// specified. Xcode must verify it.
@MainActor @Observable
final class HistoryStartController {
    /// The status the transcript's top overlay draws: a spinner while loading, "Try again" on failure.
    private(set) var state: HistoryStartPaginationState
    @ObservationIgnored private var machine: HistoryStartPagination

    init(initiallyVisible: Bool) {
        let machine = HistoryStartPagination(initiallyVisible: initiallyVisible)
        self.machine = machine
        self.state = machine.state
    }

    /// The machine's geometry for the transcript's current scroll numbers. Upstream:
    /// `packages/app/src/agent-stream/native-history-start-geometry.ts:1` and `strategy-native.tsx:207`.
    ///
    /// - `topOverlayInset` is 0: the host does not know its own top overlay inset yet (upstream passes
    ///   the real one from `useStreamTopOverlayInset`).
    /// - `isReady` approximates upstream's layout-measured readiness (`viewportMeasuredForKey` and
    ///   `contentMeasuredForKey`): it is true once the store has loaded and both heights are non-zero.
    ///   This is a known divergence; a page can be requested before the first layout pass measures.
    /// - `prefetchDistance` is the transcript's own prefetch window, in points from the top. Inside it
    ///   the transcript reports itself at the start, so a page is fetched about four screens ahead
    ///   rather than at upstream's 96 pt threshold. That is deliberate (W1 measured floors): do not
    ///   change it to 96.
    func geometry(
        contentHeight: Double, viewportHeight: Double, offsetY: Double,
        prefetchDistance: Double, store: ConversationStore
    ) -> HistoryStartGeometry {
        let isLoaded = store.phase == .ready
        var geometry = HistoryStartGeometryProvider.geometry(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            offsetY: offsetY,
            topOverlayInset: 0,
            hasOlderHistory: store.timeline.hasOlder,
            isLoadingOlderHistory: store.isLoadingOlder,
            isReady: isLoaded && viewportHeight > 0 && contentHeight > 0,
            progressKey: Self.progressKey(store))
        if offsetY <= prefetchDistance {
            geometry.distanceFromHistoryStart = 0
        }
        return geometry
    }

    /// Upstream `progressKey` (`agent-stream/view.tsx:559`): the timeline's epoch and the first loaded row's seq. It
    /// moves when a page prepends, and is nil while the timeline holds no rows.
    private static func progressKey(_ store: ConversationStore) -> String? {
        guard let cursor = store.timeline.startCursor else { return nil }
        return cursor.epoch + ":" + String(cursor.seq)
    }

    /// The generation of the page load the caller must start when non-nil, and then report with
    /// `loadCompleted(generation:applied:)`. Nil in every other state, including while `.loading`
    /// or `.settling`, so a watchdog tick can never start a fetch.
    func update(_ geometry: HistoryStartGeometry?) -> Int? {
        let requested = machine.update(geometry)
        publish()
        return requested
    }

    /// The page the machine asked for has finished. `generation` must be the value `update`
    /// returned for it; a stale one is ignored. `applied` means a page landed or the end was
    /// confirmed; false means the load failed or added nothing.
    func loadCompleted(generation: Int, applied: Bool) {
        machine.loadCompleted(generation: generation, applied: applied)
        publish()
    }

    /// The transcript is at rest: a settling page resolves to ready or dormant. Upstream `settle` is
    /// `history-start-pagination.ts:120`, run after quiet frames (`strategy-native.tsx:656`); the transcript's
    /// rest is the nearest equivalent.
    func settle(_ geometry: HistoryStartGeometry?) {
        machine.settle(geometry)
        publish()
    }

    /// "Try again", and a user's drag (upstream `rearm`: `history-start-pagination.ts:136`, called from
    /// `strategy-native.tsx:242` and `:571`). The caller asks for a page afterwards.
    func rearm() {
        machine.rearm()
        publish()
    }

    /// Publishes only a real change, so an unchanged machine never invalidates a reader.
    private func publish() {
        let next = machine.state
        if next != state {
            state = next
        }
    }
}
