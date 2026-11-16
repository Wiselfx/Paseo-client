import Foundation
import Testing

@testable import PaseoStore

// G13 lead fix: several cumulative usage events inside one turn (opencode reports per
// step) must all measure from the previous turn's final value, not from each other.
@Suite @MainActor
struct TurnUsageStepDeltaTests {
    @Test func perStepCumulativeEventsSumWithinATurn() {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        let store = ConversationStore(agentId: "agent-1", client: client)
        store.recordTurnUsage(turnId: "t1", provider: "opencode", usage: AgentUsage(outputTokens: 100, totalCostUsd: 1.0))
        store.freezeOpenUsage()
        store.recordTurnUsage(turnId: "t2", provider: "opencode", usage: AgentUsage(outputTokens: 130, totalCostUsd: 1.2))
        store.recordTurnUsage(turnId: "t2", provider: "opencode", usage: AgentUsage(outputTokens: 180, totalCostUsd: 1.5))
        store.freezeOpenUsage()
        #expect(store.turnUsage.last?.outputTokens == 80)
        #expect(abs((store.turnUsage.last?.costUsd ?? 0) - 0.5) < 1e-9)
    }
}
