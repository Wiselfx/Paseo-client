import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

private let initialSnapshotJSON = #"""
        {"requestId":"snap","generatedAt":"2026-11-09T05:00:00.000Z","entries":[
          {"provider":"claude","status":"ready","enabled":true,"label":"Claude",
           "models":[{"provider":"claude","id":"claude-opus-5-5","label":"Opus 5.5"}]},
          {"provider":"pi","status":"loading","enabled":true,"label":"Pi"},
          {"provider":"omp","status":"loading","enabled":true,"label":"Oh My Pi"}
        ]}
        """#

private let readyUpdateJSON = #"""
        {"type":"session","message":{"type":"providers_snapshot_update","payload":{
          "cwd":"/tmp/fixture-sandbox","generatedAt":"2026-11-09T05:00:02.000Z","entries":[
            {"provider":"pi","status":"ready","enabled":true,"label":"Pi",
             "models":[{"provider":"pi","id":"zai/glm-5.3","label":"GLM-5.3"}]},
            {"provider":"omp","status":"ready","enabled":true,"label":"Oh My Pi",
             "models":[{"provider":"omp","id":"opencode-go/glm-5.3-flash","label":"GLM-5.3-Flash"}],
             "modes":[{"id":"full","label":"Full Access"}]}
          ]}}}
        """#

private let otherScopeUpdateJSON = #"""
        {"type":"session","message":{"type":"providers_snapshot_update","payload":{
          "cwd":"/tmp/another-workspace","generatedAt":"2026-11-09T05:00:03.000Z","entries":[
            {"provider":"pi","status":"unavailable","enabled":true,"error":"not installed here"}
          ]}}}
        """#

/// Regression for the M2.5a "providers missing" bug.
///
/// The daemon answers the first snapshot with providers still `loading` and pushes the finished
/// catalogue as `providers_snapshot_update`. The store must merge those entries (scoped by cwd)
/// so the pickers fill in instead of hiding every provider that is not ready yet.
@Suite @MainActor
struct ProviderCatalogUpdateTests {
    private func makeSession(_ client: FakeDaemonClient) async throws -> HostSession {
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        let info = try Load.serverInfo()
        client.push(.connected(info))
        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        return session
    }

    private func loadCatalog(_ client: FakeDaemonClient, _ session: HostSession) async {
        client.onSend(GetProvidersSnapshotRequest.self) { _ in
            try JSONDecoder().decode(
                GetProvidersSnapshotRequest.Response.self,
                from: Data(initialSnapshotJSON.utf8))
        }
        await session.agentControl.loadCatalog(cwd: "/tmp/fixture-sandbox")
    }

    @Test func aLoadingProviderFillsInFromTheIncrementalUpdate() async throws {
        let client = FakeDaemonClient()
        let session = try await makeSession(client)
        await loadCatalog(client, session)

        #expect(session.agentControl.phase == .ready)
        #expect(session.agentControl.providers.map(\.provider) == ["claude", "pi", "omp"])
        #expect(session.agentControl.provider("pi")?.status == .loading)
        #expect(session.agentControl.readyProviders.map(\.provider) == ["claude"])

        client.push(
            .unhandled(
                messageType: "providers_snapshot_update", raw: Data(readyUpdateJSON.utf8)))

        let filled = await eventually { session.agentControl.provider("pi")?.status == .ready }
        #expect(filled, "the update must replace the loading entry")
        #expect(session.agentControl.phase == .ready)
        #expect(session.agentControl.provider("pi")?.label == "Pi")
        #expect(
            session.agentControl.models(forProvider: "pi").map(\.id) == ["zai/glm-5.3"])
        #expect(session.agentControl.provider("omp")?.modes?.map(\.id) == ["full"])
        #expect(
            session.agentControl.readyProviders.map(\.provider).sorted() == ["claude", "omp", "pi"])
        // The entry the update did not mention stays exactly as the snapshot had it.
        #expect(session.agentControl.provider("claude")?.status == .ready)
    }

    @Test func updatesForAnotherWorkspaceAreIgnored() async throws {
        let client = FakeDaemonClient()
        let session = try await makeSession(client)
        await loadCatalog(client, session)

        client.push(
            .unhandled(
                messageType: "providers_snapshot_update", raw: Data(otherScopeUpdateJSON.utf8)))

        try await Task.sleep(for: .milliseconds(100))
        #expect(
            session.agentControl.provider("pi")?.status == .loading,
            "a catalogue for another cwd must not replace the one on screen")
    }

    @Test func anUpdateBeforeAnyLoadIsIgnored() async throws {
        let client = FakeDaemonClient()
        let session = try await makeSession(client)

        client.push(
            .unhandled(
                messageType: "providers_snapshot_update", raw: Data(readyUpdateJSON.utf8)))

        try await Task.sleep(for: .milliseconds(100))
        #expect(session.agentControl.providers.isEmpty)
        #expect(session.agentControl.phase == .idle)
    }
}
