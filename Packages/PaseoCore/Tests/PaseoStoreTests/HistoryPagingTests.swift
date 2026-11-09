import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// U3: `loadAllOlder()` pages backwards until the daemon says there is nothing older.
/// The transcript's top-of-viewport auto-load and the Jump-to-message sheet both need the rest
/// of the conversation, not one 40-entry page.
@Suite @MainActor
struct HistoryPagingTests {
    nonisolated private static let epoch = "epoch-u3"

    /// A projected page built from plain seq numbers; each row is one user message.
    nonisolated private static func page(
        direction: String, seqs: ClosedRange<Int>, hasOlder: Bool
    ) throws -> FetchAgentTimelineRequest.Response {
        let entries = seqs.map { seq in
            #"""
            {"provider":"opencode","item":{"type":"user_message","text":"prompt \#(seq)"},
             "timestamp":"2026-11-08T21:00:00.000Z","seqStart":\#(seq),"seqEnd":\#(seq)}
            """#
        }
        let json = #"""
            {"requestId":"r","agentId":"agent-u3","direction":"\#(direction)","epoch":"\#(epoch)",
             "reset":false,"staleCursor":false,"gap":false,
             "window":{"minSeq":\#(seqs.lowerBound),"maxSeq":\#(seqs.upperBound),
                       "nextSeq":\#(seqs.upperBound + 1)},
             "hasOlder":\#(hasOlder),"hasNewer":false,
             "entries":[\#(entries.joined(separator: ","))],"error":null}
            """#
        return try JSONDecoder().decode(
            FetchAgentTimelineRequest.Response.self, from: Data(json.utf8))
    }

    private func openStore(
        _ client: FakeDaemonClient,
        timeline: @escaping @Sendable (FetchAgentTimelineRequest) async throws ->
            FetchAgentTimelineRequest.Response
    ) async throws -> ConversationStore {
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline(timeline)
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        return store
    }

    @Test func pagesUntilHasOlderIsFalse() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { request in
            switch request.direction {
            case .tail: return try Self.page(direction: "tail", seqs: 10...12, hasOlder: true)
            case .before:
                if request.cursor?.seq == 10 {
                    return try Self.page(direction: "before", seqs: 5...7, hasOlder: true)
                }
                return try Self.page(direction: "before", seqs: 1...3, hasOlder: false)
            case .after: return try Self.page(direction: "after", seqs: 12...12, hasOlder: false)
            }
        }

        await store.loadAllOlder()

        #expect(store.timeline.rows.map(\.seqStart) == [1, 2, 3, 5, 6, 7, 10, 11, 12])
        #expect(!store.timeline.hasOlder)
        #expect(store.backgroundError == nil)
        let older = client.requests(FetchAgentTimelineRequest.self).filter { $0.direction == .before }
        #expect(older.count == 2)
        #expect(older.map(\.cursor?.seq) == [10, 5], "each page asks before the oldest row it has")
    }

    @Test func stopsWhenAPageDoesNotMoveTheCursor() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { request in
            switch request.direction {
            case .tail: return try Self.page(direction: "tail", seqs: 10...12, hasOlder: true)
            // Overlapping rows: nothing is prepended, so the start cursor stays at 10 while the
            // daemon keeps saying there is more. One page, then stop.
            case .before: return try Self.page(direction: "before", seqs: 10...12, hasOlder: true)
            case .after: return try Self.page(direction: "after", seqs: 12...12, hasOlder: false)
            }
        }

        await store.loadAllOlder()

        #expect(store.timeline.hasOlder, "the daemon's answer is unchanged")
        let older = client.requests(FetchAgentTimelineRequest.self).filter { $0.direction == .before }
        #expect(older.count == 1, "a page that changes nothing cannot drive a loop")
        #expect(store.timeline.rows.map(\.seqStart) == [10, 11, 12])
    }

    @Test func stopsOnAFailedPage() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { request in
            switch request.direction {
            case .tail: return try Self.page(direction: "tail", seqs: 10...12, hasOlder: true)
            case .before: throw FakeDaemonClient.FakeError.noHandler("older page")
            case .after: return try Self.page(direction: "after", seqs: 12...12, hasOlder: false)
            }
        }

        await store.loadAllOlder()

        #expect(store.backgroundError != nil)
        #expect(store.actionError == nil, "background paging stays off the composer")
        let older = client.requests(FetchAgentTimelineRequest.self).filter { $0.direction == .before }
        #expect(older.count == 1)
    }

    @Test func doesNothingWhenTheTailIsAlreadyWhole() async throws {
        let client = FakeDaemonClient()
        let store = try await openStore(client) { request in
            try Self.page(direction: request.direction.rawValue, seqs: 10...12, hasOlder: false)
        }

        await store.loadAllOlder()

        let older = client.requests(FetchAgentTimelineRequest.self).filter { $0.direction == .before }
        #expect(older.isEmpty)
    }
}
