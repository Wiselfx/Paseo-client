import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The context-window meter, fed from snapshot fixtures and live stream events.
@Suite @MainActor
struct ConversationContextTests {
    private func makeStore() -> ConversationStore {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        return ConversationStore(agentId: "agent-1", client: client)
    }

    @Test func contextUsageComesFromTheSnapshot() throws {
        let store = makeStore()
        let agents = try Load.agents()
        let fixture = try #require(agents.entries.first?.agent)
        store.applyAgent(fixture)

        let context = try #require(store.contextUsage)
        #expect(context.usedTokens == fixture.lastUsage?.contextWindowUsedTokens)
        #expect(context.maxTokens == 1_048_576)
        #expect(context.percentUsed != nil)
        if let used = context.usedTokens, let max = context.maxTokens, let percent = context.percentUsed {
            #expect(percent == Double(used) / Double(max) * 100)
        }
    }

    @Test func contextUsageIsNilForAnAgentWithoutUsage() throws {
        let store = makeStore()
        var snapshot = try Self.minimalAgent()
        snapshot.lastUsage = nil
        store.applyAgent(snapshot)
        #expect(store.contextUsage == nil)
    }

    @Test func streamWindowFieldsMergeIntoTheSnapshot() async throws {
        let store = makeStore()
        var snapshot = try Self.minimalAgent()
        snapshot.lastUsage = AgentUsage(
            inputTokens: 1_000_000, cachedInputTokens: 100_000, outputTokens: 50_000,
            totalCostUsd: 12.5, contextWindowMaxTokens: 1_048_576,
            contextWindowUsedTokens: 400_000)
        store.applyAgent(snapshot)

        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "usage_updated",
            "provider": "opencode",
            "turnId": "turn-1",
            "usage": ["contextWindowUsedTokens": 500_000, "sessionCacheHitRatePct": 91.5],
        ])
        await store.handleStream(payload)

        let context = store.contextUsage
        #expect(context?.usedTokens == 500_000)
        #expect(context?.maxTokens == 1_048_576)
        // Cumulative counters are untouched by stream events.
        #expect(context?.inputTokens == 1_000_000)
        #expect(context?.outputTokens == 50_000)
        #expect(context?.totalCostUsd == 12.5)
        // Cache figures stay with the snapshot; stream events only move the window.
        #expect(context?.sessionCacheHitRatePct == nil)
    }

    @Test func streamEventWithoutWindowFieldsLeavesTheSnapshotAlone() async throws {
        let store = makeStore()
        var snapshot = try Self.minimalAgent()
        snapshot.lastUsage = AgentUsage(
            inputTokens: 1_000_000, outputTokens: 50_000, totalCostUsd: 12.5,
            contextWindowMaxTokens: 1_048_576, contextWindowUsedTokens: 400_000)
        store.applyAgent(snapshot)

        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_completed",
            "turnId": "turn-1",
            "usage": ["inputTokens": 79_621, "cachedInputTokens": 227_072, "outputTokens": 501],
        ])
        await store.handleStream(payload)

        let context = store.contextUsage
        #expect(context?.usedTokens == 400_000)
        #expect(context?.maxTokens == 1_048_576)
        #expect(context?.inputTokens == 1_000_000)
        #expect(context?.totalCostUsd == 12.5)
    }

    @Test func turnCompletedWithWindowFieldsRaisesTheMeter() async throws {
        let store = makeStore()
        var snapshot = try Self.minimalAgent()
        snapshot.lastUsage = AgentUsage(
            contextWindowMaxTokens: 1_000_000, contextWindowUsedTokens: 100_000)
        store.applyAgent(snapshot)

        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_completed",
            "turnId": "turn-2",
            "usage": ["contextWindowUsedTokens": 300_000, "cacheWriteTokens": 42_000],
        ])
        await store.handleStream(payload)

        #expect(store.contextUsage?.usedTokens == 300_000)
        #expect(store.contextUsage?.maxTokens == 1_000_000)
        // Non-window keys on stream events are deliberately not merged.
        #expect(store.agent?.lastUsage?.cacheWriteTokens == nil)
    }

    // MARK: Per-turn usage series (G13 C16)

    /// A completed turn's own figures land in the series, in completion order.
    @Test func turnCompletedRecordsItsUsage() async throws {
        let store = makeStore()
        for (index, output) in [120, 340].enumerated() {
            let payload = try Self.streamPayload(agentId: "agent-1", event: [
                "type": "turn_completed",
                "turnId": "turn-\(index)",
                "usage": ["outputTokens": output, "totalCostUsd": 0.01],
            ])
            await store.handleStream(payload)
        }
        #expect(store.turnUsage.map(\.outputTokens) == [120, 340])
        #expect(store.turnUsage.map(\.turnId) == ["turn-0", "turn-1"])
    }

    /// A completion without figures records nothing: the chart starts where data
    /// starts, never with fake zeros.
    @Test func turnCompletedWithoutFiguresRecordsNothing() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_completed",
            "turnId": "turn-1",
            "usage": ["contextWindowUsedTokens": 10],
        ])
        await store.handleStream(payload)
        #expect(store.turnUsage.isEmpty)
    }

    /// Nonsense figures (negatives) never become bars.
    @Test func negativeFiguresAreSkipped() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_completed",
            "turnId": "turn-1",
            "usage": ["outputTokens": -5, "totalCostUsd": -0.1],
        ])
        await store.handleStream(payload)
        #expect(store.turnUsage.isEmpty)
    }

    /// The store keeps three chart windows; the chart reads the last one.
    @Test func seriesIsBoundedAndWindowed() async throws {
        let store = makeStore()
        for index in 0..<100 {
            store.recordTurnUsage(
                turnId: "turn-\(index)",
                usage: AgentUsage(outputTokens: index, totalCostUsd: 0.01))
        }
        #expect(store.turnUsage.count == TurnUsagePoint.keepWindow)
        #expect(store.turnUsage.first?.outputTokens == 10)
        #expect(store.recentTurnUsage.count == TurnUsagePoint.chartWindow)
        #expect(store.recentTurnUsage.first?.outputTokens == 70)
        #expect(store.recentTurnUsage.last?.outputTokens == 99)
    }

    private static func minimalAgent() throws -> AgentSnapshot {
        let object: [String: Any] = [
            "id": "agent-1",
            "provider": "opencode",
            "cwd": "/tmp/fixture-usage",
            "workspaceId": "ws-1",
            "model": "claude-sonnet-4-5",
            "title": "Fixture agent",
            "status": "idle",
            "createdAt": "2026-11-09T00:00:00.000Z",
            "updatedAt": "2026-11-09T00:00:01.000Z",
            "availableModes": [],
            "pendingPermissions": [],
        ]
        return try JSONDecoder().decode(
            AgentSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static func streamPayload(
        agentId: String, event: [String: Any]
    ) throws -> AgentStreamPayload {
        let object: [String: Any] = [
            "agentId": agentId,
            "event": event,
            "timestamp": "2026-11-09T00:00:00.000Z",
        ]
        return try JSONDecoder().decode(
            AgentStreamPayload.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
