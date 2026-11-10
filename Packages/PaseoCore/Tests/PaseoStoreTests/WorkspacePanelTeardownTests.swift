import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Batch D: the workspace panel closes its checkout and detaches its terminals when it goes away.
/// These tests pin the store behaviour the panel's `releaseWorkspaceWork` relies on: a close
/// must win over a load that was already in flight, and a cancelled open must not repopulate.
@Suite @MainActor
struct WorkspacePanelTeardownTests {
    // MARK: Checkout

    @Test func checkoutLoadDoesNotSubscribeAfterClose() async throws {
        let client = FakeDaemonClient()
        let gate = Gate()
        client.on(CheckoutStatusRequest.self) { _ in try Load.checkoutStatus() }
        client.on(SubscribeCheckoutDiffRequest.self) { _ in
            await gate.wait()
            return try Load.checkoutDiff()
        }

        let store = CheckoutStore(workspace: try Load.sandboxWorkspace(), client: client)
        store.update(serverInfo: try Load.workspaceServerInfo())
        let load = Task { await store.load() }
        #expect(await eventually { !client.requests(SubscribeCheckoutDiffRequest.self).isEmpty })

        await store.close()
        await gate.open()
        await load.value

        // The response landed after the close: no subscription, no diff.
        #expect(store.diff == nil)
        #expect(store.diffPhase == .loading)
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    @Test func gitExtrasLoadDoesNotSubscribeAfterClose() async throws {
        let client = FakeDaemonClient()
        let checkout = CheckoutStore(workspace: try Load.sandboxWorkspace(), client: client)
        let store = GitExtrasStore(client: client)
        store.update(serverInfo: try modernServerInfo())
        let extras = store.workspace(for: checkout)
        let gate = Gate()
        client.on(DiffSubscribeRequest.self) { request in
            await gate.wait()
            return DiffSubscribePayload(
                requestId: request.requestId, subscriptionId: "diff-late", slot: 3, error: nil)
        }

        let load = Task { await extras.loadDiff(compare: .working(cwd: checkout.cwd)) }
        #expect(await eventually { !client.requests(DiffSubscribeRequest.self).isEmpty })

        await store.close(checkout.workspaceId)
        await gate.open()
        await load.value

        #expect(extras.snapshot == nil)
        // `close()` reset the phase; the late response must not put it back to loading/ready.
        #expect(extras.diffPhase == .idle)
        #expect(client.requests(SubscriptionReleaseRequest.self).isEmpty)
    }

    // MARK: Terminals

    @Test func closeDetachesAttachedTerminalsAndClearsTheWorkspace() async throws {
        let client = FakeDaemonClient()
        client.onListTerminals { _ in try Self.listResponse() }
        client.onListScripts { _ in try Self.scriptListResponse() }
        client.onSubscribeTerminal { _ in try Self.subscribeResponse() }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")
        store.handle(
            messageType: "terminals_changed",
            raw: try Fixture.terminalData("terminals_changed_001"))
        let terminalId = try #require(try Self.createResponse().terminal?.id)
        _ = await store.attach(terminalId, size: TerminalSize(rows: 24, cols: 80))
        #expect(store.isAttached(terminalId))

        store.close(workspaceId: "w1")

        #expect(!store.isAttached(terminalId))
        #expect(store.terminals(in: "w1").isEmpty)
        #expect(await eventually { !client.messages(of: UnsubscribeTerminalRequest.self).isEmpty })
    }

    @Test func cancelledOpenDoesNotRepopulateTheTerminalList() async throws {
        let client = FakeDaemonClient()
        let gate = Gate()
        client.onListTerminals { _ in
            await gate.wait()
            return try Self.listResponse()
        }
        client.onListScripts { _ in try Self.scriptListResponse() }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        let open = Task { await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox") }
        #expect(await eventually { !client.requests(ListTerminalsRequest.self).isEmpty })

        open.cancel()
        await gate.open()
        await open.value

        #expect(store.terminals(in: "w1").isEmpty)
    }

    // MARK: Helpers

    private func modernServerInfo() throws -> ServerInfo {
        let json = """
            {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
              "diffSubscription":true,"checkoutDiscardChanges":true,
              "workspaceFileEditing":true,"ownedSubscriptions":true
            }}
            """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    nonisolated private static func listResponse() throws -> ListTerminalsRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ListTerminalsRequest.Response>.self,
            from: Fixture.terminalData("list_terminals_response")
        ).payload
    }

    nonisolated private static func createResponse() throws -> CreateTerminalRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<CreateTerminalRequest.Response>.self,
            from: Fixture.terminalData("create_terminal_response")
        ).payload
    }

    nonisolated private static func subscribeResponse() throws -> SubscribeTerminalRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<SubscribeTerminalRequest.Response>.self,
            from: Fixture.terminalData("subscribe_terminal_response")
        ).payload
    }

    nonisolated private static func scriptListResponse() throws -> ListWorkspaceScriptsRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ListWorkspaceScriptsRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_list_response", scenario: "scripts")
        ).payload
    }
}
