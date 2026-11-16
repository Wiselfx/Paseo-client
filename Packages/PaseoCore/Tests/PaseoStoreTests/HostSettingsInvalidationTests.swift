import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// T18: slash-command cache invalidation (upstream `agent-commands/cache/index.ts` +
/// `data/push-router.ts`) and the host-diagnostics store slot (`diagnostics.request`,
/// gated on `features.daemonDiagnostics`).
@Suite @MainActor
struct HostSettingsInvalidationTests {
    private func serverInfo(features: [String: JSONValue]) throws -> ServerInfo {
        var info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self,
            from: Fixture.hostSettings("server_info")).payload
        info.features = features
        return info
    }

    private func commandsClient() throws -> (FakeDaemonClient, HostSettingsStore) {
        let client = FakeDaemonClient()
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<ListCommandsRequest.Response>.self,
            from: Fixture.hostSettings("list_commands_response")).payload
        client.onSend(ListCommandsRequest.self) { _ in response }
        return (client, HostSettingsStore(client: client))
    }

    private func snapshotUpdateRaw(entries: String) -> Data {
        Data(
            """
            {"type":"session","message":{"type":"providers_snapshot_update","payload":{
              "cwd":"/tmp/fixture-sandbox","entries":[\(entries)]}}}
            """.utf8)
    }

    private let readyEntry = """
        {"provider":"pi","status":"ready","enabled":true,"source":"builtin",
         "models":[{"provider":"pi","id":"m-1","label":"M1"}],
         "modes":[{"id":"auto","label":"Auto"}]}
        """

    @Test func firstSnapshotUpdateSeedsBaselineWithoutInvalidating() async throws {
        let (_, store) = try commandsClient()
        _ = await store.loadCommands(for: "agent-1")
        #expect(store.commands(for: "agent-1").count == 25)

        store.handle(
            messageType: "providers_snapshot_update",
            raw: snapshotUpdateRaw(entries: readyEntry))

        #expect(
            store.commands(for: "agent-1").count == 25,
            "initial discovery is ignored upstream; it must not refetch")
    }

    @Test func relevantProviderChangeInvalidatesCommands() async throws {
        let (client, store) = try commandsClient()
        _ = await store.loadCommands(for: "agent-1")
        store.handle(
            messageType: "providers_snapshot_update",
            raw: snapshotUpdateRaw(entries: readyEntry))

        // Models changed: a relevant field, so the cached menu is dropped and refetched.
        let changedModels = """
            {"provider":"pi","status":"ready","enabled":true,"source":"builtin",
             "models":[{"provider":"pi","id":"m-2","label":"M2"}],
             "modes":[{"id":"auto","label":"Auto"}]}
            """
        store.handle(
            messageType: "providers_snapshot_update",
            raw: snapshotUpdateRaw(entries: changedModels))

        #expect(store.commands(for: "agent-1").isEmpty)
        _ = await store.loadCommands(for: "agent-1")
        #expect(client.requests(ListCommandsRequest.self).count == 2)
        #expect(store.commands(for: "agent-1").count == 25)
    }

    @Test func nonRelevantProviderChurnKeepsCommands() async throws {
        let (_, store) = try commandsClient()
        _ = await store.loadCommands(for: "agent-1")
        store.handle(
            messageType: "providers_snapshot_update",
            raw: snapshotUpdateRaw(entries: readyEntry))

        // Label and fetchedAt only: not in upstream's `relevant` set, so no refetch.
        let churned = """
            {"provider":"pi","status":"ready","enabled":true,"source":"builtin",
             "label":"Pi (renamed)","fetchedAt":"2026-11-09T06:00:00.000Z",
             "models":[{"provider":"pi","id":"m-1","label":"M1"}],
             "modes":[{"id":"auto","label":"Auto"}]}
            """
        store.handle(
            messageType: "providers_snapshot_update",
            raw: snapshotUpdateRaw(entries: churned))

        #expect(store.commands(for: "agent-1").count == 25)
    }

    @Test func reconnectInvalidatesCommands() async throws {
        let (_, store) = try commandsClient()
        let info = try serverInfo(features: ["daemonDiagnostics": .bool(true)])
        store.serverInfoChanged(info)
        _ = await store.loadCommands(for: "agent-1")

        // HostSession reports every `.connected`; the second one is a reconnect.
        store.serverInfoChanged(info)
        #expect(store.commands(for: "agent-1").isEmpty)
    }

    @Test func diagnosticsAreUnsupportedQuietlyOnUngatedDaemons() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try serverInfo(features: [:]))

        #expect(!store.supportsDaemonDiagnostics)
        #expect(store.diagnosticsState == .unsupported)

        let ran = await store.loadDiagnostics()
        #expect(!ran)
        #expect(store.diagnosticsState == .unsupported)
        #expect(store.error == nil, "unsupported must stay quiet, no error spam")
        #expect(client.requests(DaemonDiagnosticsRequest.self).isEmpty)
    }

    @Test func diagnosticsRunWhenTheDaemonAdvertisesTheFeature() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try serverInfo(features: ["daemonDiagnostics": .bool(true)]))
        client.onSend(DaemonDiagnosticsRequest.self) { _ in
            DaemonDiagnosticsRequest.Response(requestId: "r-1", diagnostic: "daemon ok")
        }

        let ran = await store.loadDiagnostics()

        #expect(ran)
        #expect(store.diagnosticsState == .ready("daemon ok"))
        #expect(client.requests(DaemonDiagnosticsRequest.self).count == 1)
    }

    @Test func diagnosticsFailureIsStoredNotThrown() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try serverInfo(features: ["daemonDiagnostics": .bool(true)]))
        // No handler registered: the fake errors, which must land in the state.
        let ran = await store.loadDiagnostics()

        #expect(!ran)
        if case .failed(let message) = store.diagnosticsState {
            #expect(!message.isEmpty)
        } else {
            Issue.record("expected .failed, got \(store.diagnosticsState)")
        }
    }
}
