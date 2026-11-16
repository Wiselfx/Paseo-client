import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M7e: live + archived history, rename/archive/unarchive/delete. Fixtures were captured from
/// the fixture sandbox daemon by `Tools/capture-agent-lifecycle.mjs` (two throwaway agents, both
/// deleted afterwards).
@Suite @MainActor
struct AgentLifecycleStoreTests {
    // MARK: Helpers

    private func historyPayload(_ name: String) throws -> FetchAgentHistoryRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentHistoryRequest.Response>.self,
            from: Fixture.data(name, in: "agent-lifecycle")
        ).payload
    }

    private struct FetchAgentEnvelope: Decodable {
        var requestId: String
        var agent: AgentSnapshot?
        var project: ProjectPlacement?
        var error: String?
    }

    private func fetchAgentPayload() throws -> FetchAgentEnvelope {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentEnvelope>.self,
            from: Fixture.data("fetch_agent_response", in: "agent-lifecycle")
        ).payload
    }

    private func refreshPayload() throws -> RefreshAgentRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<RefreshAgentRequest.Response>.self,
            from: Fixture.data("refresh_agent_response", in: "agent-lifecycle")
        ).payload
    }

    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    private func archivePayload(_ name: String) throws -> ArchiveAgentRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ArchiveAgentRequest.Response>.self,
            from: Fixture.data(name, in: "agent-lifecycle")
        ).payload
    }

    private func deletePayload(_ name: String) throws -> DeleteAgentRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<DeleteAgentRequest.Response>.self,
            from: Fixture.data(name, in: "agent-lifecycle")
        ).payload
    }

    // MARK: Decoding

    @Test func historyPageOneDecodes() throws {
        let page = try historyPayload("history_page1")
        #expect(page.entries.count == 1)
        let agent = try #require(page.entries.first?.agent)
        #expect(agent.id == "00000000-0000-0000-0000-000000000002")
        #expect(agent.archivedAt != nil)
        #expect(page.pageInfo.hasMore)
        #expect(page.pageInfo.nextCursor != nil)
    }

    @Test func historyPageTwoDecodesWithNoCursor() throws {
        let page = try historyPayload("history_page2")
        #expect(page.entries.count == 1)
        #expect(page.entries.first?.agent.id == "00000000-0000-0000-0000-000000000001")
        #expect(page.pageInfo.hasMore == false)
        #expect(page.pageInfo.nextCursor == nil)
    }

    @Test func fetchAgentDecodesLiveSnapshot() throws {
        let payload = try fetchAgentPayload()
        #expect(payload.agent?.archivedAt == nil)
        #expect(payload.agent?.status == .idle)
    }

    // MARK: Store behavior

    @Test func loadFillsFirstPageAndPagination() async throws {
        let page = try historyPayload("history_page1")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        let store = AgentLifecycleStore(client: client)

        await store.load()

        #expect(store.phase == .ready)
        #expect(store.entries.map(\.id) == ["00000000-0000-0000-0000-000000000002"])
        #expect(store.hasMore)
        #expect(store.nextCursor == page.pageInfo.nextCursor)
        #expect(store.error == nil)
    }

    @Test func loadMoreAppendsAndDeduplicates() async throws {
        let page1 = try historyPayload("history_page1")
        let page2 = try historyPayload("history_page2")
        let client = FakeDaemonClient()
        let calls = Counter()
        client.on(FetchAgentHistoryRequest.self) { _ in
            calls.value += 1
            return calls.value == 1 ? page1 : page2
        }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        await store.loadMore()

        #expect(Set(store.entries.map(\.id)) == [
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0000-000000000002",
        ])
        #expect(store.hasMore == false)
        #expect(store.isLoadingMore == false)
    }

    @Test func unarchiveSendsRefreshAndClearsArchivedAt() async throws {
        let page = try historyPayload("history_page2") // holds agent A, archived
        let refresh = try refreshPayload()
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(RefreshAgentRequest.self) { _ in refresh }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        #expect(store.entries.first?.archivedAt != nil)

        let ok = await store.unarchive(agentId: "00000000-0000-0000-0000-000000000001")

        #expect(ok)
        #expect(store.entries.first?.archivedAt == nil)
        #expect(client.requests(RefreshAgentRequest.self).count == 1)
    }

    @Test func archiveMarksEntryArchived() async throws {
        let page = try historyPayload("history_page2")
        let archive = try archivePayload("archive_agent_response_a")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(ArchiveAgentRequest.self) { _ in archive }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        // Simulate the entry being live before archiving (the fixture shows it archived).
        let ok = await store.archive(agentId: "00000000-0000-0000-0000-000000000001")

        #expect(ok)
        #expect(store.entries.first?.archivedAt == archive.archivedAt)
        #expect(client.requests(ArchiveAgentRequest.self).count == 1)
    }

    @Test func renameUpdatesTitle() async throws {
        let page = try historyPayload("history_page2")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(UpdateAgentRequest.self) { _ in
            try JSONDecoder().decode(
                AgentActionResponse.self,
                from: Data(
                    #"{"requestId":"r","agentId":"a","accepted":true,"error":null}"#.utf8))
        }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        let ok = await store.rename(agentId: "00000000-0000-0000-0000-000000000001", to: "renamed")

        #expect(ok)
        #expect(store.entries.first?.title == "renamed")
        #expect(client.requests(UpdateAgentRequest.self).count == 1)
    }

    @Test func deleteRemovesEntry() async throws {
        let page = try historyPayload("history_page2")
        let delete = try deletePayload("delete_agent_response_a")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(DeleteAgentRequest.self) { _ in delete }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        #expect(store.entries.count == 1)

        let ok = await store.delete(agentId: "00000000-0000-0000-0000-000000000001")

        #expect(ok)
        #expect(store.entries.isEmpty)
        #expect(client.requests(DeleteAgentRequest.self).count == 1)
    }

    @Test func unarchiveFailureKeepsArchivedAndReports() async throws {
        struct Boom: Error {}
        let page = try historyPayload("history_page2")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(RefreshAgentRequest.self) { _ in throw Boom() }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        let ok = await store.unarchive(agentId: "00000000-0000-0000-0000-000000000001")

        #expect(!ok)
        #expect(store.entries.first?.archivedAt != nil)
        #expect(store.actionError != nil)
    }
}
