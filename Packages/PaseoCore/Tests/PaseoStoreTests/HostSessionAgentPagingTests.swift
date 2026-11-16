import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// `refreshAgents` pages the whole directory the way upstream's directory sync does: one page at
/// a time, subscribing on the first only, and stopping when the host stops naming a next cursor.
@Suite @MainActor
struct HostSessionAgentPagingTests {
    @Test func twoPagesAreMerged() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { request in
            if request.page?.cursor == nil {
                return try Self.page(
                    ids: ["agent-1", "agent-2"], subscriptionId: "sub-1",
                    nextCursor: "page-2", hasMore: true)
            }
            return try Self.page(ids: ["agent-3"], nextCursor: nil, hasMore: false)
        }

        let session = HostSession(client: client)
        await session.start()

        let requests = client.requests(FetchAgentsRequest.self)
        #expect(requests.count == 2)
        #expect(requests.first?.page?.cursor == nil)
        #expect(requests.last?.page?.cursor == "page-2")
        #expect(session.agents.count == 3)
        #expect(session.agents.contains { $0.id == "agent-3" })
        #expect(session.agentsError == nil)
    }

    @Test func subscribeIsSentOnTheFirstPageOnly() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { request in
            if request.page?.cursor == nil {
                return try Self.page(
                    ids: ["agent-1"], subscriptionId: "sub-1", nextCursor: "page-2", hasMore: true)
            }
            return try Self.page(ids: ["agent-2"], nextCursor: nil, hasMore: false)
        }

        let session = HostSession(client: client)
        await session.start()

        let requests = client.requests(FetchAgentsRequest.self)
        #expect(requests.count == 2)
        #expect(requests.first?.subscribe != nil)
        #expect(requests.last?.subscribe == nil)
        #expect(requests.allSatisfy { $0.page?.limit == FetchAgentsRequest.maxPageLimit })
        #expect(requests.allSatisfy { $0.scope == "active" })
        #expect(requests.allSatisfy { $0.sort == [.updatedAtDescending] })
    }

    @Test func missingPageInfoMeansOnePage() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in
            try Self.page(ids: ["agent-1", "agent-2"])
        }

        let session = HostSession(client: client)
        await session.start()

        #expect(client.requests(FetchAgentsRequest.self).count == 1)
        #expect(session.agents.count == 2)
    }

    /// A cursor the host repeats must not spin: the second read of the same page ends the loop.
    @Test func aRepeatedCursorStopsTheLoop() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { request in
            if request.page?.cursor == nil {
                return try Self.page(ids: ["agent-1"], nextCursor: "page-2", hasMore: true)
            }
            return try Self.page(ids: ["agent-2"], nextCursor: "page-2", hasMore: true)
        }

        let session = HostSession(client: client)
        await session.start()

        #expect(client.requests(FetchAgentsRequest.self).count == 2)
        #expect(session.agents.count == 2)
    }

    /// `includeBackground` is only sent to a host that advertises the feature, so an older daemon
    /// never sees a field it does not know.
    @Test func backgroundAgentsAreRequestedOnlyFromHostsThatHaveThem() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Self.page(ids: ["agent-1"]) }

        let session = HostSession(client: client)
        await session.start()
        #expect(client.requests(FetchAgentsRequest.self).last?.includeBackground == nil)

        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.serverInfo != nil })
        await session.refreshAgents()
        #expect(client.requests(FetchAgentsRequest.self).last?.includeBackground == true)
    }

    @Test func theRequestCarriesTheDirectoryFieldsFlat() throws {
        let request = FetchAgentsRequest(
            page: .init(limit: 200, cursor: "page-2"), subscribe: true, scope: "active",
            includeBackground: true, sort: [.updatedAtDescending])
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let message = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])["message"]
                as? [String: Any]

        #expect(message?["type"] as? String == "fetch_agents_request")
        #expect(message?["scope"] as? String == "active")
        #expect(message?["includeBackground"] as? Bool == true)
        #expect(message?["subscribe"] is [String: Any])
        let page = message?["page"] as? [String: Any]
        #expect(page?["limit"] as? Int == 200)
        #expect(page?["cursor"] as? String == "page-2")
        let sort = message?["sort"] as? [[String: Any]]
        #expect(sort?.first?["key"] as? String == "updated_at")
        #expect(sort?.first?["direction"] as? String == "desc")

        // Omitted fields stay off the wire; a host must never receive `null` for them.
        let bare = try JSONEncoder().encode(
            SessionRequestEnvelope(FetchAgentsRequest(page: .init(limit: 200), subscribe: true)))
        let bareMessage = try #require(
            try JSONSerialization.jsonObject(with: bare) as? [String: Any])["message"]
                as? [String: Any]
        #expect(bareMessage?["scope"] == nil)
        #expect(bareMessage?["includeBackground"] == nil)
        #expect(bareMessage?["sort"] == nil)
    }

    // MARK: Helpers

    /// A `fetch_agents_response` payload with one minimal agent per id.
    nonisolated private static func page(
        ids: [String], subscriptionId: String? = nil, nextCursor: String? = nil,
        hasMore: Bool? = nil
    ) throws -> FetchAgentsRequest.Response {
        let entries = ids.enumerated().map { index, id in
            """
            {"agent": {"id": "\(id)", "provider": "claude", "cwd": "/tmp/fixture-sandbox", \
            "workspaceId": "wks_fixture", "status": "idle", \
            "createdAt": "2026-11-0\(index + 1)T00:00:00.000Z", \
            "updatedAt": "2026-11-0\(index + 1)T00:00:00.000Z", \
            "availableModes": [], "pendingPermissions": []}}
            """
        }.joined(separator: ",")
        var payload = #"{"requestId":"agents","entries":[\#(entries)]"#
        if let subscriptionId { payload += #","subscriptionId":"\#(subscriptionId)""# }
        if let hasMore {
            let cursor = nextCursor.map { #""\#($0)""# } ?? "null"
            payload += #","pageInfo":{"nextCursor":\#(cursor),"prevCursor":null,"hasMore":\#(hasMore)}"#
        }
        payload += "}"

        let frame = #"{"type":"session","message":{"type":"fetch_agents_response","payload":\#(payload)}}"#
        return try JSONDecoder()
            .decode(SessionPayloadEnvelope<FetchAgentsRequest.Response>.self, from: Data(frame.utf8))
            .payload
    }
}
