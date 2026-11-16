import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M11: `ImportSessionStore` over scrubbed synthetic fixtures with FakeDaemonClient.
@Suite @MainActor
struct ImportSessionStoreTests {
    private func listResponse() throws -> FetchRecentProviderSessionsRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchRecentProviderSessionsRequest.Response>.self,
            from: Fixture.importSession("fetch_recent_provider_sessions_response")).payload
    }

    private func serverInfo(features: [String: JSONValue]) throws -> ServerInfo {
        var info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self,
            from: Fixture.hostSettings("server_info")).payload
        info.features = features
        return info
    }

    @Test func loadAggregatesPerProviderAndSortsNewestFirst() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        let response = try listResponse()
        client.onSend(FetchRecentProviderSessionsRequest.self) { _ in response }

        await store.load(providers: ["pi"], cwd: "/tmp/fixture-sandbox", limit: 15)

        #expect(store.phase == .ready)
        #expect(store.entries.count == 2)
        #expect(store.entries[0].id == "pi:fixture-handle-1")
        #expect(store.entries[1].id == "pi:fixture-handle-2")
        #expect(store.alreadyImportedCount == 0)
        #expect(store.providerErrors.isEmpty)
        #expect(!store.hasMore, "a short page is the end of the provider's list")
        let sent = try #require(client.requests(FetchRecentProviderSessionsRequest.self).first)
        #expect(sent.cwd == "/tmp/fixture-sandbox")
        #expect(sent.providers == ["pi"])
        #expect(sent.limit == 15)
        #expect(sent.query == nil, "no search flag, no query on the wire")
    }

    @Test func queryIsSentOnlyWhenTheDaemonAdvertisesSearch() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        store.serverInfoChanged(
            try serverInfo(features: ["importSessionSearch": .bool(true)]))
        #expect(store.supportsSearch)
        let response = try listResponse()
        client.onSend(FetchRecentProviderSessionsRequest.self) { _ in response }

        await store.load(providers: ["pi"], cwd: nil, query: "flaky", limit: 15)

        #expect(client.requests(FetchRecentProviderSessionsRequest.self).first?.query == "flaky")
        #expect(client.requests(FetchRecentProviderSessionsRequest.self).first?.cwd == nil)
    }

    @Test func aFailedProviderBecomesANErrorRowWhileOthersStillList() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        let response = try listResponse()
        // No handler: every request throws, so both providers must surface as error rows.
        await store.load(providers: ["pi", "claude"], cwd: nil, limit: 15)

        #expect(store.entries.isEmpty)
        #expect(store.providerErrors.map(\.provider) == ["pi", "claude"])
        #expect(store.phase == .failed(store.providerErrors[0].message))
        _ = response
    }

    @Test func fullPageMeansHasMoreUntilTheCeiling() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        let response = try listResponse()  // 2 entries
        client.onSend(FetchRecentProviderSessionsRequest.self) { _ in response }

        await store.load(providers: ["pi"], cwd: nil, limit: 2)
        #expect(store.hasMore)
        await store.load(providers: ["pi"], cwd: nil, limit: 200)
        #expect(!store.hasMore, "the protocol ceiling has no next page")
        #expect(ImportSessionStore.nextPageLimit(15) == 45)
        #expect(ImportSessionStore.nextPageLimit(200) == 200)
    }

    @Test func importReturnsTheNewAgent() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        let entry = try listResponse().entries[0]
        client.onSend(ImportAgentRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ImportAgentRequest.Response>.self,
                from: Fixture.importSession("import_agent_resumed_status")).payload
        }

        let agent = await store.importSession(entry, cwd: "/tmp/fixture-sandbox", workspaceId: "wks_fixture")

        #expect(agent?.id == "fixture-imported-agent-1")
        #expect(store.actionError == nil)
        #expect(store.importingId == nil)
        let sent = try #require(client.requests(ImportAgentRequest.self).first)
        #expect(sent.providerId == "pi")
        #expect(sent.providerHandleId == "fixture-handle-1")
        #expect(sent.workspaceId == "wks_fixture")
    }

    @Test func importFailureCarriesTheDaemonError() async throws {
        let client = FakeDaemonClient()
        let store = ImportSessionStore(client: client)
        let entry = try listResponse().entries[0]
        client.onSend(ImportAgentRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ImportAgentRequest.Response>.self,
                from: Fixture.importSession("import_agent_failed_status")).payload
        }

        let agent = await store.importSession(entry)

        #expect(agent == nil)
        #expect(store.actionError == "session not found on host")
    }

    @Test func importTargetFollowsUpstreamResolveImportTarget() {
        // Scoped listing: daemon already matched, id goes out.
        #expect(
            ImportSessionStore.importTargetWorkspaceId(
                entryCwd: "/tmp/fixture-sandbox", workspaceCwd: "/tmp/fixture-sandbox",
                workspaceId: "wks-1", isScopedListing: true, supportsWorkspaceTarget: true) == "wks-1")
        // Show-all listing: path comparison decides.
        #expect(
            ImportSessionStore.importTargetWorkspaceId(
                entryCwd: "/tmp/fixture-sandbox", workspaceCwd: "/tmp/fixture-sandbox/",
                workspaceId: "wks-1", isScopedListing: false, supportsWorkspaceTarget: true) == "wks-1")
        #expect(
            ImportSessionStore.importTargetWorkspaceId(
                entryCwd: "/tmp/other", workspaceCwd: "/tmp/fixture-sandbox",
                workspaceId: "wks-1", isScopedListing: false, supportsWorkspaceTarget: true) == nil)
        // Ungated daemon: never send a target.
        #expect(
            ImportSessionStore.importTargetWorkspaceId(
                entryCwd: "/tmp/fixture-sandbox", workspaceCwd: "/tmp/fixture-sandbox",
                workspaceId: "wks-1", isScopedListing: true, supportsWorkspaceTarget: false) == nil)
    }

    @Test func displayFallbacksMatchUpstreamWording() throws {
        let entries = try listResponse().entries
        #expect(entries[0].displayTitle == "Fix the flaky test")
        #expect(entries[0].promptPreview == "Now run the suite again")
        #expect(entries[1].displayTitle == "Untitled session")
        #expect(entries[1].promptPreview == "No prompt preview")
    }
}
