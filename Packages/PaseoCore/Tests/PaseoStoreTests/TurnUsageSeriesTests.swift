import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The per-turn usage series (G13 C16 review): usage is attributed to turns by time,
/// deltas come from session totals, and resets restart the baseline.
@Suite @MainActor
struct TurnUsageSeriesTests {
    private func makeStore() -> ConversationStore {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        return ConversationStore(agentId: "agent-1", client: client)
    }

    private func usage(output: Int? = nil, cost: Double? = nil) -> AgentUsage {
        AgentUsage(outputTokens: output, totalCostUsd: cost)
    }

    // MARK: Attribution by time

    /// pi-style: `turn_completed` carries no usage; a later usage event for the
    /// same turn lands on the turn it belongs to (the point stays open).
    @Test func completionWithoutUsageThenUsageEvent() {
        let store = makeStore()
        store.recordTurnUsage(turnId: "t1", provider: "pi", usage: usage())
        #expect(store.recentTurnUsage.isEmpty)
        store.recordTurnUsage(
            turnId: "t1", provider: "pi", usage: usage(output: 500, cost: 0.05))
        let points = store.recentTurnUsage
        #expect(points.count == 1)
        #expect(points[0].turnId == "t1")
        #expect(points[0].outputTokens == 500)
        // First observation has no previous: no cost bar.
        #expect(points[0].costUsd == 0)
    }

    /// A figure without a turn id lands on the open turn (the usage poller's
    /// post-completion publish carries the id, but the rule does not need it).
    @Test func figureWithoutTurnIdLandsOnOpenTurn() {
        let store = makeStore()
        store.openUsageTurnID = "t1"
        store.recordTurnUsage(turnId: nil, provider: "pi", usage: usage(output: 40))
        #expect(store.recentTurnUsage.map(\.turnId) == ["t1"])
    }

    /// A figure with no turn context at all is dropped, not misattributed.
    @Test func figureWithoutAnyTurnIsDropped() {
        let store = makeStore()
        store.recordTurnUsage(turnId: nil, provider: "pi", usage: usage(output: 40))
        #expect(store.recentTurnUsage.isEmpty)
    }

    /// The next turn's start freezes the open point.
    @Test func nextTurnStartFreezesTheOpenPoint() {
        let store = makeStore()
        store.recordTurnUsage(turnId: "t1", provider: "pi", usage: usage(output: 500))
        store.freezeOpenUsage()
        store.openUsageTurnID = "t2"
        #expect(store.turnUsage.map(\.turnId) == ["t1"])
        #expect(store.openUsageTurnID == "t2")
    }

    // MARK: Deltas (opencode-style cumulative session totals)

    /// Cumulative session totals become per-turn bars.
    @Test func cumulativeTotalsGivePerTurnDeltas() {
        let store = makeStore()
        store.recordTurnUsage(
            turnId: "t1", provider: "opencode", usage: usage(output: 1000, cost: 0.50))
        store.freezeOpenUsage()
        store.openUsageTurnID = "t2"
        store.recordTurnUsage(
            turnId: "t2", provider: "opencode", usage: usage(output: 1500, cost: 0.70))
        let points = store.recentTurnUsage
        #expect(points.count == 2)
        #expect(points[0].outputTokens == 1000)
        #expect(points[0].costUsd == 0)
        #expect(points[1].outputTokens == 500)
        #expect(abs(points[1].costUsd - 0.2) < 1e-9)
    }

    /// claude's output tokens arrive per-query: the latest wins, never a delta.
    /// Its cost is possibly cumulative: the delta rule still applies.
    @Test func claudeTokensTakeLatestCostDeltas() {
        let store = makeStore()
        store.recordTurnUsage(turnId: "t1", provider: "claude", usage: usage(output: 300))
        store.recordTurnUsage(turnId: "t1", provider: "claude", usage: usage(output: 250))
        #expect(store.recentTurnUsage.map(\.outputTokens) == [250])
        store.recordTurnUsage(
            turnId: "t1", provider: "claude", usage: usage(cost: 0.50))
        store.recordTurnUsage(
            turnId: "t1", provider: "claude", usage: usage(cost: 0.90))
        let costs = store.recentTurnUsage.map(\.costUsd)
        #expect(costs.count == 1)
        #expect(abs(costs[0] - 0.4) < 1e-9)
    }

    // MARK: Resets and bounds

    /// A drop is a session reset (new session/rewind): no negative bars, the
    /// baseline restarts, and the next growth measures from there.
    @Test func resetDoesNotGoNegative() {
        let store = makeStore()
        store.recordTurnUsage(
            turnId: "t1", provider: "opencode", usage: usage(output: 100, cost: 0.10))
        store.recordTurnUsage(
            turnId: "t1", provider: "opencode", usage: usage(output: 50, cost: 0.05))
        // The reset turn draws no bar at all — not a negative, not a bogus zero
        // dressed as data. The baseline restarts underneath.
        #expect(store.recentTurnUsage.isEmpty)
        store.recordTurnUsage(
            turnId: "t1", provider: "opencode", usage: usage(output: 80, cost: 0.09))
        let after = store.recentTurnUsage
        #expect(after.count == 1)
        #expect(after[0].outputTokens == 30)
        #expect(abs(after[0].costUsd - 0.04) < 1e-9)
    }

    /// A turn of pure zeros records nothing.
    @Test func allZeroTurnRecordsNothing() {
        let store = makeStore()
        store.recordTurnUsage(
            turnId: "t1", provider: "opencode", usage: usage(output: 0, cost: 0))
        store.freezeOpenUsage()
        #expect(store.turnUsage.isEmpty)
    }

    /// The store keeps three chart windows; the chart reads the last one.
    @Test func seriesIsBoundedAndWindowed() {
        let store = makeStore()
        for index in 0..<100 {
            store.recordTurnUsage(
                turnId: "turn-\(index)", provider: "opencode",
                usage: usage(output: 1000 + index, cost: 0.01))
        }
        #expect(store.turnUsage.count == TurnUsagePoint.keepWindow)
        #expect(store.turnUsage.first?.turnId == "turn-9")
        #expect(store.recentTurnUsage.count == TurnUsagePoint.chartWindow)
        #expect(store.openUsageTurnID == "turn-99")
    }

    // MARK: Wiring

    /// `turn_completed` with usage records it on the turn (opencode fixture agent).
    @Test func streamCompletionRecordsUsage() async throws {
        let store = makeStore()
        let object: [String: Any] = [
            "agentId": "agent-1",
            "event": [
                "type": "turn_completed",
                "turnId": "turn-1",
                "usage": ["outputTokens": 100, "totalCostUsd": 0.1],
            ] as [String: Any],
            "timestamp": "2026-11-09T00:00:00.000Z",
        ]
        let payload = try JSONDecoder().decode(
            AgentStreamPayload.self,
            from: JSONSerialization.data(withJSONObject: object))
        await store.handleStream(payload)
        #expect(store.recentTurnUsage.map(\.outputTokens) == [100])
    }
}
