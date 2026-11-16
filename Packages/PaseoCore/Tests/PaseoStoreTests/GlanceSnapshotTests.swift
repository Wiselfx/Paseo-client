import Foundation
import Testing

@testable import PaseoStore

// Phase E G14: the glance snapshot — redaction, ordering, Codable round-trip.
struct GlanceSnapshotTests {
    private func agent(
        id: String, title: String, attention: Bool = false, updatedAt: Date? = nil
    ) -> GlanceSnapshot.Agent {
        GlanceSnapshot.Agent(
            id: id, title: title, hostServerID: "srv", status: "idle",
            requiresAttention: attention, pendingPermissionCount: 0,
            updatedAt: updatedAt)
    }

    @Test("hidden names become generic, shown names survive")
    func redaction() {
        #expect(GlanceSnapshot.redactedTitle("My chat", showAgentNames: false) == "Agent")
        #expect(GlanceSnapshot.redactedTitle("My chat", showAgentNames: true) == "My chat")
        #expect(GlanceSnapshot.redactedTitle(nil, showAgentNames: true) == "Agent")
        #expect(GlanceSnapshot.redactedTitle("  ", showAgentNames: true) == "Agent")
    }

    @Test("attention sorts first, then recency")
    func sorting() {
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        let sorted = GlanceSnapshot.sortAgents([
            agent(id: "a", title: "A", updatedAt: new),
            agent(id: "b", title: "B", attention: true, updatedAt: old),
            agent(id: "c", title: "C", updatedAt: new),
        ])
        #expect(sorted.map(\.id) == ["b", "a", "c"])
    }

    @Test("codable round-trips exactly")
    func codableRoundTrip() throws {
        let snapshot = GlanceSnapshot(
            agents: [
                agent(id: "a", title: "A", attention: true, updatedAt: Date(timeIntervalSince1970: 1500))
            ],
            runningCount: 2,
            capturedAt: Date(timeIntervalSince1970: 1600))
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(GlanceSnapshot.self, from: data) == snapshot)
    }
}
