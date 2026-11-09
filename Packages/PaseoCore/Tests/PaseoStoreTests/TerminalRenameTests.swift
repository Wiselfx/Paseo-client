import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct TerminalRenameTests {
    @Test func renameSendsTheRPCAndRefreshesTheList() async throws {
        let client = FakeDaemonClient()
        client.onListTerminals { _ in try Self.listResponse() }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        client.on(RenameTerminalRequest.self) { request in
            #expect(request.terminalId == "terminal-fixture-1")
            #expect(request.title == "Renamed")
            return try Self.renameResponse()
        }
        let ok = await store.renameTerminal("terminal-fixture-1", to: "Renamed", in: "w1")
        #expect(ok == true)
        #expect(client.requests(RenameTerminalRequest.self).count == 1)
        #expect(await eventually { client.requests(ListTerminalsRequest.self).count >= 2 })
        #expect(store.error == nil)
    }

    @Test func renameRejectsEmptyTitlesWithoutAnyRequest() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        let ok = await store.renameTerminal("terminal-fixture-1", to: "   ")
        #expect(ok == false)
        #expect(client.requests(RenameTerminalRequest.self).isEmpty)
        #expect(store.error == "A title is required.")
    }

    @Test func renameFailureSurfacesTheDaemonError() async throws {
        let client = FakeDaemonClient()
        client.on(RenameTerminalRequest.self) { _ in
            try JSONDecoder().decode(
                SessionPayloadEnvelope<RenameTerminalRequest.Response>.self,
                from: Data("""
                    {"type":"session","message":{"type":"terminal.rename.response","payload":{
                      "requestId":"fixture","success":false,"error":"no such terminal"
                    }}}
                    """.utf8)).payload
        }
        let store = TerminalsStore(client: client)
        let ok = await store.renameTerminal("terminal-fixture-1", to: "Name")
        #expect(ok == false)
        #expect(store.error == "no such terminal")
    }

    @Test func renameResponseDecodesTheLiveFixture() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<RenameTerminalRequest.Response>.self,
            from: Fixture.terminalData("terminal_rename_response")).payload
        #expect(response.success == true)
        #expect(response.error == nil)
    }

    nonisolated private static func listResponse() throws -> ListTerminalsRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ListTerminalsRequest.Response>.self,
            from: Fixture.terminalData("list_terminals_response")
        ).payload
    }

    nonisolated private static func renameResponse() throws -> RenameTerminalRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<RenameTerminalRequest.Response>.self,
            from: Fixture.terminalData("terminal_rename_response")
        ).payload
    }
}
