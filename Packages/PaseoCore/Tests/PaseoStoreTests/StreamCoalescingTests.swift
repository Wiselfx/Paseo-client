import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// P5-A: live `.timeline` deltas are coalesced into one commit per display frame, and the
/// store still holds the full text afterwards.
@Suite @MainActor
struct StreamCoalescingTests {
    /// A store loaded with the fixture tail cut just before the streamed turn.
    private func makeStore(_ client: FakeDaemonClient) async throws -> ConversationStore {
        client.onFetchTimeline { _ in try Load.page(before: 8) }
        let store = ConversationStore(agentId: try Load.fixtureAgentId(), client: client)
        await store.load()
        return store
    }

    /// The rows the fixture stream must produce, applied to a fresh state.
    private func expectedRows() throws -> [TimelineRow] {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        for payload in try Load.stream() {
            _ = state.applyStream(payload)
        }
        return state.rows
    }

    @Test func theFirstDeltaOfABurstFlushesImmediately() async throws {
        let client = FakeDaemonClient()
        let store = try await makeStore(client)
        let coalescer = TimelineCommitCoalescer(store: store, frameInterval: .seconds(30))
        let payload = try #require(try Load.stream().first { $0.seq == 8 })
        let baseline = store.turnCommits

        coalescer.enqueue(payload)

        // Leading edge: applied synchronously, without waiting for the frame timer.
        #expect(store.timeline.rows.contains { $0.seqStart == 8 })
        #expect(store.turnCommits == baseline + 1)
    }

    @Test func bufferedDeltasAreCommittedTogetherAndNothingIsDropped() async throws {
        let client = FakeDaemonClient()
        let store = try await makeStore(client)
        let coalescer = TimelineCommitCoalescer(store: store, frameInterval: .seconds(30))
        let payloads = try Load.stream().filter { $0.seq != nil }
        let expected = try expectedRows()
        let baseline = store.turnCommits

        coalescer.enqueue(payloads[0])
        let leadingRowCount = store.timeline.rows.count
        for payload in payloads.dropFirst() {
            coalescer.enqueue(payload)
        }
        // Still buffered: the frame timer has not fired.
        #expect(store.timeline.rows.count == leadingRowCount)

        coalescer.flush()

        #expect(store.timeline.rows == expected)
        #expect(store.turns == TurnBuilder.turns(from: store.timeline.rows, activeTurnId: store.activeTurnId))
        // Leading flush + one merged trailing flush: two commits for the whole burst.
        #expect(store.turnCommits == baseline + 2)
    }

    @Test func aBurstOverTheSessionStreamCommitsLessThanOnePerDelta() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { request in
            request.direction == .tail ? try Load.page(before: 8) : try Load.page()
        }
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }

        let payloads = try Load.stream().filter { if case .timeline = $0.event { true } else { false } }
        let expected = try expectedRows()
        let baseline = store.turnCommits

        for payload in payloads {
            client.push(.agentStream(payload))
        }

        let done = await eventually { store.timeline.rows == expected }
        #expect(done)
        #expect(store.turns == TurnBuilder.turns(from: store.timeline.rows, activeTurnId: store.activeTurnId))
        #expect(
            store.turnCommits - baseline < payloads.count,
            "a burst must commit fewer times than it has deltas")
    }
}
