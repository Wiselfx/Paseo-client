import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

private func searchFixtureResponse(
    epoch: String = "epoch-1", locations: String, nextCursor: Int? = nil, error: String? = nil
) throws -> AgentTimelineSearchRequest.Response {
    let cursor = nextCursor.map(String.init) ?? "null"
    let errorValue = error.map { "\"\($0)\"" } ?? "null"
    let json = #"""
        {"requestId":"r","agentId":"agent-1","epoch":"\#(epoch)",
         "locations":[\#(locations)],"nextCursor":\#(cursor),"error":\#(errorValue)}
        """#
    return try JSONDecoder().decode(
        AgentTimelineSearchRequest.Response.self, from: Data(json.utf8))
}



/// T12: in-conversation search returns locations and follows the daemon's page cursor.
@Suite @MainActor
struct ConversationSearchTests {
    @Test func searchFollowsEveryPageAndKeepsLocationsInOrder() async throws {
        let client = FakeDaemonClient()
        client.onSend(AgentTimelineSearchRequest.self) { request in
            if request.cursor == nil {
                return try searchFixtureResponse(
                    locations: #"{"seq":4,"role":"user","count":2}"#, nextCursor: 4)
            }
            return try searchFixtureResponse(
                locations: #"{"seq":9,"role":"assistant","count":1}"#)
        }
        let store = ConversationStore(agentId: "agent-1", client: client)

        let result = await store.search.search("  ready  ")

        #expect(result?.query == "ready")
        #expect(store.search.query == "ready")
        #expect(store.search.epoch == "epoch-1")
        #expect(store.search.locations.map(\.seq) == [4, 9])
        #expect(store.search.matchCount == 3)
        #expect(store.search.nextCursor == nil)
        #expect(store.search.error == nil)
        #expect(!store.search.isSearching)
        #expect(client.requests(AgentTimelineSearchRequest.self).map(\.cursor) == [nil, 4])
        #expect(client.requests(AgentTimelineSearchRequest.self).allSatisfy { $0.query == "ready" })
    }

    @Test func firstPageCanBeLoadedThenContinued() async throws {
        let client = FakeDaemonClient()
        client.onSend(AgentTimelineSearchRequest.self) { request in
            if request.cursor == nil {
                return try searchFixtureResponse(
                    locations: #"{"seq":4,"role":"user"}"#, nextCursor: 4)
            }
            return try searchFixtureResponse(locations: #"{"seq":9,"role":"assistant"}"#)
        }
        let store = ConversationStore(agentId: "agent-1", client: client)

        let first = await store.search.search("ready", followPages: false)
        #expect(first?.nextCursor == 4)
        #expect(store.search.nextCursor == 4)
        #expect(store.search.locations.map(\.seq) == [4])

        await store.search.loadMore()
        #expect(store.search.locations.map(\.seq) == [4, 9])
        #expect(store.search.nextCursor == nil)
        #expect(client.requests(AgentTimelineSearchRequest.self).map(\.cursor) == [nil, 4])
    }

    @Test func emptyQueryClearsWithoutAnRPC() async throws {
        let client = FakeDaemonClient()
        client.onSend(AgentTimelineSearchRequest.self) { _ in
            try searchFixtureResponse(locations: #"{"seq":1,"role":"user"}"#)
        }
        let store = ConversationStore(agentId: "agent-1", client: client)
        _ = await store.search.search("ready")
        #expect(store.search.locations.count == 1)

        let result = await store.search.search("   ")

        #expect(result == nil)
        #expect(store.search.query.isEmpty)
        #expect(store.search.locations.isEmpty)
        #expect(client.requests(AgentTimelineSearchRequest.self).count == 1)
    }

    @Test func daemonAndTransportFailuresLandInError() async throws {
        let client = FakeDaemonClient()
        client.onSend(AgentTimelineSearchRequest.self) { _ in
            try searchFixtureResponse(locations: "", error: "History changed; search again")
        }
        let store = ConversationStore(agentId: "agent-1", client: client)
        let rejected = await store.search.search("ready")
        #expect(rejected == nil)
        #expect(store.search.error == "History changed; search again")

        client.onSend(AgentTimelineSearchRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("search")
        }
        await store.search.search("again")
        #expect(store.search.error != nil)
        #expect(store.search.locations.isEmpty)
    }

    @Test func anEpochChangeDuringPagingStopsTheSearch() async throws {
        let client = FakeDaemonClient()
        client.onSend(AgentTimelineSearchRequest.self) { request in
            if request.cursor == nil {
                return try searchFixtureResponse(
                    epoch: "epoch-1", locations: #"{"seq":4,"role":"user"}"#, nextCursor: 4)
            }
            return try searchFixtureResponse(
                epoch: "epoch-2", locations: #"{"seq":9,"role":"assistant"}"#)
        }
        let store = ConversationStore(agentId: "agent-1", client: client)

        let result = await store.search.search("ready")

        #expect(result == nil)
        #expect(store.search.error?.contains("changed") == true)
        #expect(store.search.locations.map(\.seq) == [4], "never mixes rows from two epochs")
    }
}
