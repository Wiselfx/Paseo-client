import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M14: the usage overview roll-up over agent `lastUsage`, DSH's session-list fallback.
@Suite struct UsageOverviewTests {
    private func agent(updatedAt: String, input: Int, output: Int, costByModel: [(String, Int)] = []) throws -> AgentSnapshot {
        var snapshot = try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentsRequest.Response>.self,
            from: Fixture.data("fetch_agents_response")).payload.entries[0].agent
        snapshot.updatedAt = updatedAt
        snapshot.lastUsage = AgentUsage(
            inputTokens: input, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens: output,
            costByModel: costByModel.map {
                AgentModelCost(key: $0.0, costUsd: 0.01, tokens: $0.1)
            })
        return snapshot
    }

    @Test func totalsAndFavoriteModel() throws {
        let agents = [
            try agent(updatedAt: "2026-11-09T10:00:00.000Z", input: 100, output: 50,
                      costByModel: [("model-a", 150)]),
            try agent(updatedAt: "2026-11-08T10:00:00.000Z", input: 200, output: 100,
                      costByModel: [("model-a", 60), ("model-b", 240)]),
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = try #require(formatter.date(from: "2026-11-09T12:00:00.000Z"))
        let overview = UsageOverviewBuilder.compute(agents: agents, dayCount: 14, now: now)

        #expect(overview.sessions == 2)
        #expect(overview.tokens == 450)
        #expect(overview.activeDays == 2)
        #expect(overview.peakHour == 10)
        #expect(overview.peakHourLabel == "10 AM")
        #expect(overview.favoriteModel == "model-b")
        #expect(overview.models.map(\.model) == ["model-b", "model-a"])
        #expect(overview.models.map(\.tokens) == [240, 210])
        #expect(overview.days.count == 14)
        #expect(overview.days.last?.tokens == 150)
        #expect(overview.days.first?.tokens == 0)
    }

    @Test func emptyListIsQuiet() {
        let overview = UsageOverviewBuilder.compute(agents: [], dayCount: 14)
        #expect(overview.sessions == 0)
        #expect(overview.tokens == 0)
        #expect(overview.activeDays == 0)
        #expect(overview.peakHour == nil)
        #expect(overview.favoriteModel == nil)
        #expect(overview.days.allSatisfy { $0.tokens == 0 })
    }

    @Test func yardstickLineMatchesDshWording() {
        #expect(UsageBooks.funLine(forTokens: 100) == nil)
        #expect(
            UsageBooks.funLine(forTokens: 40_100) == "You've used ~1× the tokens in Animal Farm.")
        #expect(
            UsageBooks.funLine(forTokens: 3_000_000)
                == "You've used ~2× the tokens in In Search of Lost Time.")
    }
}
