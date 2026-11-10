import Foundation
import Observation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// R3 §2: the agent-list aggregates and the incremental, in-place upsert.
@Suite @MainActor
struct HostSessionAggregatesTests {
    // MARK: - Deterministic RNG

    private struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(in range: Range<Int>) -> Int {
            precondition(!range.isEmpty)
            return range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func bool() -> Bool { next() & 1 == 1 }
    }

    /// Counts writes to `HostSession.agents`, re-arming after each one, so a test can tell one
    /// notification from two.
    private final class AgentListWrites: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { locked { value } }

        func recordAndRearm(_ session: HostSession) {
            locked { value += 1 }
            Task { @MainActor in Self.arm(session, writes: self) }
        }

        @MainActor static func arm(_ session: HostSession, writes: AgentListWrites) {
            withObservationTracking {
                _ = session.agents
            } onChange: {
                writes.recordAndRearm(session)
            }
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }
    }

    // MARK: - Snapshots

    private static let decoder = JSONDecoder()

    /// An `AgentSnapshot` with just the fields this test cares about.
    private static func snapshot(
        id: String,
        updatedAt: String,
        status: String = "idle",
        attention: Bool = false,
        permissionIds: [String] = [],
        archivedAt: String? = nil,
        title: String? = nil
    ) throws -> AgentSnapshot {
        let permissions =
            permissionIds.map { #"{"id":"\#($0)"}"# }.joined(separator: ",")
        let archived = archivedAt.map { ",\"archivedAt\":\"\($0)\"" } ?? ""
        let titleField = title.map { ",\"title\":\"\($0)\"" } ?? ""
        let json = #"""
            {"id":"\#(id)","provider":"pi","cwd":"/tmp/fixture-sandbox","status":"\#(status)",
             "createdAt":"2026-11-08T20:00:00.000Z","updatedAt":"\#(updatedAt)",
             "availableModes":[],"pendingPermissions":[\#(permissions)],
             "requiresAttention":\#(attention)\#(archived)\#(titleField)}
            """#
        return try decoder.decode(AgentSnapshot.self, from: Data(json.utf8))
    }

    private nonisolated static func emptyResponse() throws -> FetchAgentsRequest.Response {
        try JSONDecoder().decode(
            FetchAgentsRequest.Response.self,
            from: Data(#"{"requestId":"r","entries":[]}"#.utf8))
    }

    private func startedSession(_ client: FakeDaemonClient) async throws -> HostSession {
        client.onFetchAgents { _ in try Self.emptyResponse() }
        let session = HostSession(client: client)
        await session.start()
        return session
    }

    // MARK: - Tests

    @Test func countsFollowUpsertsRemovesAndArchives() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)
        #expect(session.runningAgentCount == 0)
        #expect(session.pendingPermissionCount == 0)
        #expect(session.attentionCount == 0)

        let busy = try Self.snapshot(
            id: "agent-busy", updatedAt: "2026-11-08T21:00:00.000Z", status: "running",
            attention: true, permissionIds: ["p1", "p2"])
        client.push(.agentUpdate(.upsert(busy, project: nil)))
        let busyLanded = await eventually { session.agents.count == 1 }
        #expect(busyLanded)
        #expect(session.runningAgentCount == 1)
        #expect(session.pendingPermissionCount == 2)
        #expect(session.attentionCount == 1)

        let idle = try Self.snapshot(id: "agent-idle", updatedAt: "2026-11-08T21:01:00.000Z")
        client.push(.agentUpdate(.upsert(idle, project: nil)))
        let idleLanded = await eventually { session.agents.count == 2 }
        #expect(idleLanded)
        #expect(session.runningAgentCount == 1)
        #expect(session.pendingPermissionCount == 2)
        #expect(session.attentionCount == 1)

        // Same id, now idle with one permission and no attention.
        let calmed = try Self.snapshot(
            id: "agent-busy", updatedAt: "2026-11-08T21:02:00.000Z", permissionIds: ["p1"])
        client.push(.agentUpdate(.upsert(calmed, project: nil)))
        let calmedLanded = await eventually {
            session.agents.first(where: { $0.id == "agent-busy" }) == calmed
        }
        #expect(calmedLanded)
        #expect(session.runningAgentCount == 0)
        #expect(session.pendingPermissionCount == 1)
        #expect(session.attentionCount == 0)

        client.push(.agentUpdate(.remove(agentId: "agent-idle")))
        let removed = await eventually { session.agents.count == 1 }
        #expect(removed)
        #expect(session.runningAgentCount == 0)
        #expect(session.pendingPermissionCount == 1)

        let archived = try Self.snapshot(
            id: "agent-busy", updatedAt: "2026-11-08T21:03:00.000Z", permissionIds: ["p1"],
            archivedAt: "2026-11-08T21:03:00.000Z")
        client.push(.agentUpdate(.upsert(archived, project: nil)))
        let archivedGone = await eventually { session.agents.isEmpty }
        #expect(archivedGone)
        #expect(session.runningAgentCount == 0)
        #expect(session.pendingPermissionCount == 0)
        #expect(session.attentionCount == 0)
    }

    @Test func anIdenticalUpsertDoesNotTouchTheAgentList() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)
        let agent = try Self.snapshot(id: "agent-1", updatedAt: "2026-11-08T21:00:00.000Z")
        client.push(.agentUpdate(.upsert(agent, project: nil)))
        let landed = await eventually { session.agents.count == 1 }
        #expect(landed)

        let writes = AgentListWrites()
        AgentListWrites.arm(session, writes: writes)

        // Identical snapshot first, then a changed one. Only the second may write `agents`; the
        // first must return before assigning (its observer notification is what this counts).
        client.push(.agentUpdate(.upsert(agent, project: nil)))
        let changed = try Self.snapshot(
            id: "agent-1", updatedAt: "2026-11-08T21:05:00.000Z", title: "Renamed")
        client.push(.agentUpdate(.upsert(changed, project: nil)))
        let changedLanded = await eventually { session.agents.first?.title == "Renamed" }
        #expect(changedLanded)
        #expect(writes.count == 1, "an identical snapshot must not notify observers")

        // And an identical snapshot after a change is silent too.
        client.push(.agentUpdate(.upsert(changed, project: nil)))
        let third = try Self.snapshot(id: "agent-2", updatedAt: "2026-11-08T22:00:00.000Z")
        client.push(.agentUpdate(.upsert(third, project: nil)))
        let thirdLanded = await eventually { session.agents.contains { $0.id == "agent-2" } }
        #expect(thirdLanded)
        #expect(writes.count == 2, "only the added agent wrote the list")
    }

    @Test func fiveHundredUpsertsKeepTheFullSortOrder() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)
        var rng = SplitMix64(seed: 0xA66E_57)
        let statuses = ["idle", "running", "error", "closed"]
        let stamps = [
            "2026-11-08T21:00:00.000Z", "2026-11-08T21:05:00.000Z", "2026-11-08T21:10:00.000Z",
            "2026-11-08T20:00:00.000Z", "2026-11-08T21:00:00.000Z", "not-a-date",
        ]

        var expected: [String: AgentSnapshot] = [:]
        for _ in 0..<500 {
            let id = "agent-\(rng.int(in: 0..<60))"
            let snapshot = try Self.snapshot(
                id: id,
                updatedAt: stamps[rng.int(in: 0..<stamps.count)],
                status: statuses[rng.int(in: 0..<statuses.count)],
                attention: rng.bool(),
                permissionIds: rng.bool() ? ["p1"] : [])
            client.push(.agentUpdate(.upsert(snapshot, project: nil)))
            expected[id] = snapshot
        }

        // A sentinel proves the loop drained every earlier event: pushes are processed in order.
        let sentinel = try Self.snapshot(
            id: "agent-sentinel", updatedAt: "2030-01-01T00:00:00.000Z")
        expected[sentinel.id] = sentinel
        client.push(.agentUpdate(.upsert(sentinel, project: nil)))
        let drained = await eventually(timeout: .seconds(10)) {
            session.agents.contains { $0.id == "agent-sentinel" }
        }
        #expect(drained)

        let want = Self.referenceSorted(Array(expected.values))
        #expect(session.agents.map(\.id) == want.map(\.id))
        #expect(session.agents == want)
    }

    // MARK: - Reference order

    /// Newest `updatedAt` first, ties by id: the documented order, written out again here.
    private static func referenceSorted(_ agents: [AgentSnapshot]) -> [AgentSnapshot] {
        agents.sorted { lhs, rhs in
            let left = PaseoDate.parse(lhs.updatedAt)
            let right = PaseoDate.parse(rhs.updatedAt)
            switch (left, right) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.id < rhs.id
            }
        }
    }
}
