import Foundation
import Testing

@testable import PaseoStore

/// Transition table of upstream `createHistoryStartPagination`
/// (packages/app/src/agent-stream/history-start-pagination.ts). Each test names the upstream lines it
/// mirrors. The clock is injected, so the 15 s watchdog runs on a fixed timeline.
@Suite struct HistoryStartPaginationTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    /// A ready view, measured, at the start, with older history and a progress key.
    private func geometry(
        distance: Double = 0,
        underfilled: Bool = false,
        hasOlder: Bool = true,
        loading: Bool = false,
        ready: Bool = true,
        key: String? = "k1"
    ) -> HistoryStartGeometry {
        HistoryStartGeometry(
            distanceFromHistoryStart: distance,
            isUnderfilled: underfilled,
            hasOlderHistory: hasOlder,
            isLoadingOlderHistory: loading,
            isReady: ready,
            progressKey: key)
    }

    // MARK: - Geometry (native-history-start-geometry.ts)

    @Test func geometryKeepsTheOverlayInsetAndThe32Constant() {
        // Upstream native-history-start-geometry.ts:11: distance = max(0, offsetY - inset - 32).
        let deep = HistoryStartGeometryProvider.geometry(
            contentHeight: 1000, viewportHeight: 800, offsetY: 100, topOverlayInset: 50,
            hasOlderHistory: true, isLoadingOlderHistory: false, isReady: true, progressKey: "k")
        #expect(deep.distanceFromHistoryStart == 18)
        // Upstream native-history-start-geometry.ts:12: (content - 32 - inset) < viewport.
        #expect(deep.isUnderfilled == false, "918 is not below 800")

        let top = HistoryStartGeometryProvider.geometry(
            contentHeight: 1000, viewportHeight: 800, offsetY: 10, topOverlayInset: 50,
            hasOlderHistory: true, isLoadingOlderHistory: false, isReady: true, progressKey: "k")
        #expect(top.distanceFromHistoryStart == 0, "clamped at zero")

        let short = HistoryStartGeometryProvider.geometry(
            contentHeight: 500, viewportHeight: 800, offsetY: 0, topOverlayInset: 50,
            hasOlderHistory: false, isLoadingOlderHistory: true, isReady: false, progressKey: nil)
        #expect(short.isUnderfilled, "418 is below 800")
        #expect(short.hasOlderHistory == false)
        #expect(short.isLoadingOlderHistory)
        #expect(short.isReady == false)
        #expect(short.progressKey == nil)
    }

    // MARK: - Initial state

    @Test func startsDormantWithTheInitialVisibility() {
        #expect(HistoryStartPagination(initiallyVisible: false).state
            == HistoryStartPaginationState(status: .dormant, visible: false))
        #expect(HistoryStartPagination(initiallyVisible: true).state
            == HistoryStartPaginationState(status: .dormant, visible: true))
    }

    // MARK: - Underfilled list

    @Test func anUnderfilledListLoadsOnceWithZeroScrolling() {
        // Upstream :87 and :93-96: underfilled at the start requests from dormant, with no scroll.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        let underfilled = geometry(underfilled: true)

        guard let request = pagination.update(underfilled, now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        #expect(pagination.state.status == .loading)

        // Upstream :72: a request not completed yet never re-requests.
        #expect(pagination.update(underfilled, now: t0.addingTimeInterval(1)) == nil)
        #expect(pagination.state.status == .loading)

        pagination.loadCompleted(generation: request, applied: true)
        // Upstream :74-75: the progress key moved, so the operation settles.
        #expect(pagination.update(geometry(key: "k2"), now: t0.addingTimeInterval(2)) == nil)
        #expect(pagination.state.status == .settling)

        // Upstream :125-126: the list fills the viewport, so settling ends dormant and shown.
        pagination.settle(geometry(key: "k2"))
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: true))
    }

    // MARK: - Dormant -> loading -> settling -> dormant

    @Test func dormantLoadingSettlingDormantWhenNoOlderHistoryAfterSettle() {
        var pagination = HistoryStartPagination(initiallyVisible: false)

        // Upstream :83-85: a dormant list that fills the viewport stays dormant, and is shown.
        #expect(pagination.update(geometry(), now: t0) == nil)
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: true))

        // Upstream :137: a user drag re-arms dormant to ready (strategy-native.tsx:571).
        pagination.rearm()
        #expect(pagination.state.status == .ready)

        guard let request = pagination.update(geometry(), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        #expect(pagination.state.status == .loading)
        pagination.loadCompleted(generation: request, applied: true)

        #expect(pagination.update(geometry(key: "k2"), now: t0.addingTimeInterval(3)) == nil)
        #expect(pagination.state.status == .settling)

        // Upstream :129-130: at the start with no older history left, settling ends dormant.
        pagination.settle(geometry(distance: 10, hasOlder: false, key: "k2"))
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: true))
    }

    // MARK: - Settling -> ready

    @Test func settlingBecomesReadyWhenTheReaderHasMovedAway() {
        var pagination = HistoryStartPagination(initiallyVisible: true)
        pagination.rearm()
        guard let request = pagination.update(geometry(), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: request, applied: true)
        _ = pagination.update(geometry(key: "k2"), now: t0)
        #expect(pagination.state.status == .settling)

        // Upstream :127-128: distance > 96 after settle means the reader is no longer at the start.
        pagination.settle(geometry(distance: 300, key: "k2"))
        #expect(pagination.state == HistoryStartPaginationState(status: .ready, visible: true))
        #expect(pagination.update(geometry(distance: 300, key: "k2"), now: t0) == nil)
    }

    @Test func stillUnderfilledSettleLeavesReadyAndTheCallerRequestsTheNextPage() {
        // Upstream :131-133: settle publishes ready and calls update(), so the next page is requested
        // when the view is still underfilled. In this API the caller calls update(_:now:) after settle.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let first = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: first, applied: true)
        _ = pagination.update(geometry(underfilled: true, key: "k2"), now: t0)
        #expect(pagination.state.status == .settling)

        pagination.settle(geometry(underfilled: true, key: "k2"))
        #expect(pagination.state.status == .ready)

        #expect(pagination.update(geometry(underfilled: true, key: "k2"), now: t0) != nil)
        #expect(pagination.state.status == .loading)
    }

    // MARK: - Watchdog

    @Test func failsOnTheFifteenSecondWatchdogWhenNoFetchCompletes() {
        var pagination = HistoryStartPagination(initiallyVisible: false)
        #expect(pagination.update(geometry(underfilled: true), now: t0) != nil)

        // Upstream :63 and :62: 15 s is the limit, and it fails only once it is passed.
        #expect(pagination.update(nil, now: t0.addingTimeInterval(15)) == nil)
        #expect(pagination.state.status == .loading)

        #expect(pagination.update(geometry(underfilled: true), now: t0.addingTimeInterval(16)) == nil)
        #expect(pagination.state == HistoryStartPaginationState(status: .failed, visible: true))
    }

    @Test func aCompletedRequestWaitsForReadyAndTheWatchdogRestartsWhenReadyAgain() {
        // Upstream :53-55: a completed request with an unready view clears the timer. Upstream :56-57
        // arms it again once the view is ready.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let request = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: request, applied: true)

        #expect(pagination.update(geometry(ready: false), now: t0.addingTimeInterval(1)) == nil)
        #expect(pagination.update(geometry(ready: false), now: t0.addingTimeInterval(100)) == nil)
        #expect(pagination.state.status == .loading, "no failure while the view is not ready")

        // Ready again at 101 s: the timer restarts from here, so 115 s is still inside the window.
        #expect(pagination.update(geometry(), now: t0.addingTimeInterval(101)) == nil)
        #expect(pagination.update(geometry(), now: t0.addingTimeInterval(115)) == nil)
        #expect(pagination.state.status == .loading)
        #expect(pagination.update(geometry(), now: t0.addingTimeInterval(117)) == nil)
        #expect(pagination.state.status == .failed)
    }

    @Test func aFailedFetchFailsTheOperationAndALateCompletionIsIgnored() {
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let request = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }

        // Upstream :102-103: applied == false fails the operation.
        pagination.loadCompleted(generation: request, applied: false)
        #expect(pagination.state == HistoryStartPaginationState(status: .failed, visible: true))
        #expect(pagination.update(geometry(underfilled: true), now: t0) == nil)

        // A completion after failure belongs to no request in flight. It is ignored.
        pagination.loadCompleted(generation: request, applied: true)
        #expect(pagination.state.status == .failed)
    }

    // MARK: - Re-arm

    @Test func rearmFromFailedRequestsAgain() {
        // Upstream :137: failed -> ready. The retry button then calls update.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let failed = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: failed, applied: false)
        #expect(pagination.state.status == .failed)

        pagination.rearm()
        #expect(pagination.state == HistoryStartPaginationState(status: .ready, visible: true))
        #expect(pagination.update(geometry(), now: t0.addingTimeInterval(20)) != nil)
        #expect(pagination.state.status == .loading)
    }

    @Test func rearmLeavesALoadingOperationAlone() {
        var pagination = HistoryStartPagination(initiallyVisible: false)
        #expect(pagination.update(geometry(underfilled: true), now: t0) != nil)
        pagination.rearm()
        #expect(pagination.state.status == .loading)
    }

    // MARK: - Suppression

    @Test func aLoadInFlightSuppressesAnotherRequest() {
        // Upstream :92: isLoadingOlderHistory suppresses the request.
        var pagination = HistoryStartPagination(initiallyVisible: true)
        pagination.rearm()
        #expect(pagination.update(geometry(loading: true), now: t0) == nil)
        #expect(pagination.state.status == .ready)
        #expect(pagination.update(geometry(underfilled: true, loading: true), now: t0) == nil)
        #expect(pagination.state.status == .ready)
    }

    @Test func aMissingProgressKeySuppressesTheRequest() {
        // Upstream :92: no progress key, so no request.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        #expect(pagination.update(geometry(underfilled: true, key: nil), now: t0) == nil)
        #expect(pagination.state.status == .dormant)
        pagination.rearm()
        #expect(pagination.update(geometry(key: nil), now: t0) == nil)
        #expect(pagination.state.status == .ready)
    }

    @Test func noOlderHistoryFinishesDormant() {
        // Upstream :88-90: without older history the operation is finished, dormant.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        pagination.rearm()
        #expect(pagination.update(geometry(hasOlder: false), now: t0) == nil)
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: true))
    }

    @Test func aCompletedRequestWithNoOlderHistoryFinishesDormant() {
        // Upstream :76-77: the completed request sees the history has run out.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let request = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: request, applied: true)
        #expect(pagination.update(geometry(hasOlder: false), now: t0) == nil)
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: true))
    }

    @Test func settleIsANoOpOutsideSettling() {
        var pagination = HistoryStartPagination(initiallyVisible: false)
        pagination.settle(geometry(distance: 300))
        #expect(pagination.state == HistoryStartPaginationState(status: .dormant, visible: false))
    }

    // MARK: - Generation

    @Test func aCompletionForAnOlderGenerationIsIgnored() {
        // Upstream history-start-pagination.ts:100-101: the load resolves against its own generation.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let stale = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }

        // The watchdog fails the operation, retiring its generation (finish -> clear, :45-48).
        #expect(pagination.update(geometry(underfilled: true), now: t0.addingTimeInterval(16)) == nil)
        #expect(pagination.state.status == .failed)
        pagination.loadCompleted(generation: stale, applied: true)
        #expect(pagination.state.status == .failed, "a stale completion must not revive the operation")

        // Rearm starts a new generation; the stale one is still ignored.
        pagination.rearm()
        guard
            let fresh = pagination.update(
                geometry(underfilled: true), now: t0.addingTimeInterval(17))
        else {
            Issue.record("expected update to start a request")
            return
        }
        #expect(fresh != stale)
        pagination.loadCompleted(generation: stale, applied: true)
        #expect(pagination.state.status == .loading)
        pagination.loadCompleted(generation: fresh, applied: true)
        #expect(pagination.update(geometry(underfilled: true, key: "k2"), now: t0.addingTimeInterval(18)) == nil)
        #expect(pagination.state.status == .settling)
    }

    @Test func aCompletionAfterSettlingIsIgnored() {
        // Settle retires the generation (clear, :41-44), so a late failure for it changes nothing.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        guard let request = pagination.update(geometry(underfilled: true), now: t0) else {
            Issue.record("expected update to start a request")
            return
        }
        pagination.loadCompleted(generation: request, applied: true)
        #expect(pagination.update(geometry(key: "k2"), now: t0) == nil)
        #expect(pagination.state.status == .settling)
        pagination.settle(geometry(underfilled: true, key: "k2"))
        #expect(pagination.state.status == .ready)
        pagination.loadCompleted(generation: request, applied: false)
        #expect(pagination.state.status == .ready, "a late failure must not fail the settled operation")
    }

    // MARK: - Return value

    @Test func updateReturnsTrueExactlyOncePerRequest() {
        // Upstream :93-96: the request starts once. Later updates do not re-request.
        var pagination = HistoryStartPagination(initiallyVisible: false)
        let underfilled = geometry(underfilled: true)
        var results: [Int?] = []
        for step in 0..<5 {
            results.append(pagination.update(underfilled, now: t0.addingTimeInterval(Double(step))))
        }
        #expect(results[0] != nil)
        #expect(results[1...].allSatisfy { $0 == nil })

        // Once completed and settled, a new request is a new single generation.
        guard let first = results[0] else {
            Issue.record("expected the first update to start a request")
            return
        }
        pagination.loadCompleted(generation: first, applied: true)
        _ = pagination.update(geometry(key: "k2"), now: t0.addingTimeInterval(5))
        pagination.settle(geometry(distance: 300, key: "k2"))
        pagination.rearm()
        #expect(pagination.update(geometry(key: "k2"), now: t0.addingTimeInterval(6)) != nil)
        #expect(pagination.update(geometry(key: "k2"), now: t0.addingTimeInterval(7)) == nil)
    }
}
