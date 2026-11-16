import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M12: `ForgeSearchStore` transport selection and normalization, over scrubbed fixtures.
@Suite @MainActor
struct ForgeSearchStoreTests {
    nonisolated private func serverInfo(features: [String: JSONValue]) throws -> ServerInfo {
        var info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self,
            from: Fixture.hostSettings("server_info")).payload
        info.features = features
        return info
    }

    nonisolated private func forgeResponse() throws -> ForgeSearchRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ForgeSearchRequest.Response>.self,
            from: Fixture.forgeSearch("forge_search_response")).payload
    }

    nonisolated private func githubResponse() throws -> GitHubSearchRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<GitHubSearchRequest.Response>.self,
            from: Fixture.forgeSearch("github_search_response")).payload
    }

    @Test func forgeTransportWhenAdvertised() async throws {
        let client = FakeDaemonClient()
        let store = ForgeSearchStore(client: client)
        store.serverInfoChanged(try serverInfo(features: ["forgeSearch": .bool(true)]))
        #expect(store.supportsForgeSearch)
        client.onSend(ForgeSearchRequest.self) { _ in try forgeResponse() }

        let result = await store.search(cwd: "/tmp/fixture-sandbox", query: "flaky")

        #expect(result?.items.count == 2)
        #expect(result?.authState == .authenticated)
        #expect(result?.error == nil)
        #expect(store.error == nil)
        #expect(client.requests(ForgeSearchRequest.self).count == 1)
        #expect(client.requests(GitHubSearchRequest.self).isEmpty)
        let sent = try #require(client.requests(ForgeSearchRequest.self).first)
        #expect(sent.limit == 20)
        #expect(sent.kinds == nil, "both kinds by default")
    }

    @Test func legacyTransportWithoutTheFeature() async throws {
        let client = FakeDaemonClient()
        let store = ForgeSearchStore(client: client)
        store.serverInfoChanged(try serverInfo(features: [:]))
        #expect(!store.supportsForgeSearch)
        client.onSend(GitHubSearchRequest.self) { _ in try githubResponse() }

        let result = await store.search(
            cwd: "/tmp/fixture-sandbox", query: "flaky", kinds: [.changeRequest])

        #expect(result?.items.map(\.kind) == [.changeRequest, .issue])
        #expect(client.requests(GitHubSearchRequest.self).count == 1)
        #expect(client.requests(ForgeSearchRequest.self).isEmpty)
        #expect(client.requests(GitHubSearchRequest.self).first?.kinds == ["github-pr"])
    }

    @Test func legacyFeaturesDisabledMeansUnauthenticated() async throws {
        let client = FakeDaemonClient()
        let store = ForgeSearchStore(client: client)
        var response = try githubResponse()
        response.featuresEnabled = false
        let served = response
        client.onSend(GitHubSearchRequest.self) { _ in served }

        let result = await store.search(cwd: "/tmp/fixture-sandbox", query: "flaky")

        #expect(result?.authState == .unauthenticated)
    }

    @Test func transportFailureSetsErrorAndReturnsNil() async {
        let client = FakeDaemonClient()
        let store = ForgeSearchStore(client: client)
        // No handler registered: the fake throws.
        let result = await store.search(cwd: "/tmp/fixture-sandbox", query: "flaky")

        #expect(result == nil)
        #expect(store.error != nil)
    }
}
