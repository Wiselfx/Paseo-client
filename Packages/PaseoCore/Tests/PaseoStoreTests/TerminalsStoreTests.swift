import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct TerminalsStoreTests {
    // MARK: Capabilities and directory

    @Test func capabilitiesComeFromServerInfo() async throws {
        let store = TerminalsStore(client: FakeDaemonClient())
        #expect(!store.isSupported)

        await store.handle(connection: .connected(try Load.serverInfo()))
        #expect(store.isSupported)
        #expect(store.capabilities.restoreModes)
        #expect(store.capabilities.sizeOwnership)
        #expect(store.capabilities.inputModeReplay)
        #expect(store.capabilities.workspaceScriptManagement)
    }

    @Test func openSubscribesToTheDirectoryAndLoads() async throws {
        let client = FakeDaemonClient()
        client.onListTerminals { _ in try Self.listResponse() }
        client.onListScripts { _ in try Self.scriptListResponse() }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        #expect(await eventually { !client.requests(ListTerminalsRequest.self).isEmpty })
        #expect(client.requests(ListTerminalsRequest.self).first?.workspaceId == "w1")
        #expect(client.requests(ListTerminalsRequest.self).first?.cwd == "/tmp/fixture-sandbox")
        #expect(await eventually { !client.messages(of: SubscribeTerminalsRequest.self).isEmpty })
        let subscribe = try #require(client.messages(of: SubscribeTerminalsRequest.self).first)
        #expect(subscribe.workspaceId == "w1")
        #expect(subscribe.cwd == "/tmp/fixture-sandbox")
        #expect(await eventually { store.loadingScriptWorkspaces.isEmpty })
        #expect(store.scripts(in: "w1").first?.scriptName == "fixture")
    }

    @Test func terminalsChangedReplacesTheWholeList() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")

        store.handle(
            messageType: "terminals_changed",
            raw: try Fixture.terminalData("terminals_changed_001"))
        #expect(store.terminals(in: "w1").count == 1)
        #expect(store.terminals(in: "w1").first?.name == "fixture-terminal")

        store.handle(
            messageType: "terminals_changed",
            raw: try Fixture.terminalData("terminals_changed_002"))
        #expect(store.terminals(in: "w1").isEmpty)
    }

    @Test func createAndKillUpdateTheList() async throws {
        let client = FakeDaemonClient()
        let created = try Self.createResponse()
        client.onCreateTerminal { request in
            #expect(request.cwd == "/tmp/fixture-sandbox")
            #expect(request.workspaceId == "w1")
            #expect(request.name == "fixture-terminal")
            return created
        }
        let createdId = try #require(created.terminal?.id)
        client.onKillTerminal { request in
            #expect(request.terminalId == createdId)
            return try Self.killResponse()
        }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))

        let terminal = await store.createTerminal(
            in: "w1", cwd: "/tmp/fixture-sandbox", name: "fixture-terminal")
        #expect(terminal?.id == createdId)
        #expect(store.terminals(in: "w1").map(\.id) == [createdId])
        #expect(store.error == nil)

        #expect(await store.killTerminal(createdId))
        #expect(store.terminals(in: "w1").isEmpty)
        #expect(store.error == nil)
    }

    // MARK: Attach, replay and routing

    @Test func attachDeliversReplayMarkersAndLiveBytesBySlot() async throws {
        let client = FakeDaemonClient()
        client.onSubscribeTerminal { request in
            #expect(request.restore?.mode == .visibleSnapshot)
            #expect(request.restore?.scrollbackLines == 200)
            #expect(request.restore?.size == TerminalSize(rows: 24, cols: 80))
            return try Self.subscribeResponse()
        }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        let terminalId = try #require(try Self.createResponse().terminal?.id)

        let stream = await store.attach(
            terminalId, size: TerminalSize(rows: 24, cols: 80))
        #expect(store.isAttached(terminalId))

        for frame in try Fixture.terminalFrames() {
            store.handle(binaryFrame: frame.encoded)
        }
        store.detach(terminalId)
        #expect(!store.isAttached(terminalId))

        let outputs = await Self.collect(stream)
        #expect(outputs.count == 6)
        guard case .replayBegin(let metadata) = outputs.first else {
            Issue.record("first output should be a replay begin marker")
            return
        }
        #expect(metadata.rows == 24)
        #expect(metadata.cols == 80)
        #expect(metadata.retainedHistoryLines == 0)

        let replayText = outputs.compactMap { output -> String? in
            if case .output(let data) = output { return String(decoding: data, as: UTF8.self) }
            return nil
        }.joined()
        #expect(replayText.contains("fixture-sandbox"))
        #expect(replayText.contains("hello\r\n"))
        #expect(replayText.contains("README.md"))
        #expect(outputs.contains(.replayEnd))

        #expect(await eventually { !client.messages(of: UnsubscribeTerminalRequest.self).isEmpty })
    }

    @Test func framesForAnotherSlotAreIgnored() async throws {
        let client = FakeDaemonClient()
        client.onSubscribeTerminal { _ in try Self.subscribeResponse() }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        let terminalId = try #require(try Self.createResponse().terminal?.id)

        let stream = await store.attach(terminalId, size: TerminalSize(rows: 24, cols: 80))
        let unrelated = TerminalStreamFrame(
            opcode: .output, slot: 99, payload: Data("not ours".utf8))
        store.handle(binaryFrame: unrelated.encoded)
        store.detach(terminalId)

        #expect(await Self.collect(stream).isEmpty)
    }

    @Test func streamExitEndsTheViewStream() async throws {
        let client = FakeDaemonClient()
        client.onSubscribeTerminal { _ in try Self.subscribeResponse() }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        let terminalId = try #require(try Self.createResponse().terminal?.id)

        let stream = await store.attach(terminalId, size: TerminalSize(rows: 24, cols: 80))
        store.handle(
            messageType: "terminal_stream_exit",
            raw: try Fixture.terminalData("terminal_stream_exit_000"))

        let outputs = await Self.collect(stream)
        #expect(outputs == [.exited(error: nil)])
        #expect(!store.isAttached(terminalId))
    }

    @Test func unsupportedHostFailsAttachClosed() async throws {
        let store = TerminalsStore(client: FakeDaemonClient())
        let stream = await store.attach("t1", size: TerminalSize(rows: 24, cols: 80))
        let outputs = await Self.collect(stream)
        #expect(outputs == [.exited(error: "Update the host to view terminals.")])
    }

    @Test func reconnectResubscribesAndReattaches() async throws {
        let client = FakeDaemonClient()
        client.onListTerminals { _ in try Self.listResponse() }
        client.onListScripts { _ in try Self.scriptListResponse() }
        let counter = LockedCounter()
        client.onSubscribeTerminal { _ in
            counter.increment()
            return try Self.subscribeResponse()
        }

        let store = TerminalsStore(client: client)
        let info = try Load.serverInfo()
        await store.handle(connection: .connected(info))
        await store.open(workspaceId: "w1", cwd: "/tmp/fixture-sandbox")
        let terminalId = try #require(try Self.createResponse().terminal?.id)
        let stream = await store.attach(terminalId, size: TerminalSize(rows: 24, cols: 80))
        #expect(counter.value == 1)

        await store.handle(connection: .reconnecting(attempt: 1, lastError: .timeout))
        #expect(store.isAttached(terminalId))
        await store.handle(connection: .connected(info))

        #expect(await eventually { counter.value == 2 })
        #expect(store.isAttached(terminalId))
        #expect(await eventually { client.requests(ListTerminalsRequest.self).count >= 2 })

        // The reattached slot still routes bytes to the original stream.
        let slot = try #require(try Self.subscribeResponse().slot)
        let frame = TerminalStreamFrame(
            opcode: .output, slot: slot, payload: Data("after reconnect".utf8))
        store.handle(binaryFrame: frame.encoded)
        store.detach(terminalId)
        let outputs = await Self.collect(stream)
        #expect(outputs.contains(.output(Data("after reconnect".utf8))))
    }

    // MARK: Input, resize and capture

    @Test func inputAndResizeAreFireAndForget() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))

        store.sendInput("ls\r", to: "t1")
        store.sendInput(Data([0x03]), to: "t1")
        store.resize("t1", to: TerminalSize(rows: 40, cols: 120), intent: .claim)

        #expect(await eventually { client.messages(of: TerminalInput.self).count == 3 })
        let inputs = client.messages(of: TerminalInput.self)
        #expect(inputs.allSatisfy { $0.terminalId == "t1" })
        // The three fire-and-forget tasks race, so compare as a set rather than by send order.
        #expect(
            Set(inputs.map(\.message)) == [
                .input(data: "ls\r"),
                .input(data: "\u{03}"),
                .resize(rows: 40, cols: 120, intent: .claim),
            ])
    }

    @Test func captureReturnsLines() async throws {
        let client = FakeDaemonClient()
        client.onCaptureTerminal { request in
            #expect(request.terminalId == "t1")
            #expect(request.stripAnsi)
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<CaptureTerminalRequest.Response>.self,
                from: Data(
                    #"{"type":"session","message":{"type":"capture_terminal_response","payload":{"terminalId":"t1","lines":["hello"],"totalLines":1,"requestId":"r"}}}"#
                        .utf8)
            ).payload
        }
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        #expect(await store.capture("t1") == ["hello"])
    }

    // MARK: Scripts

    @Test func scriptListStartStopUseTheCapturedShapes() async throws {
        let client = FakeDaemonClient()
        client.onListScripts { request in
            #expect(request.workspaceId == "w1")
            return try Self.scriptListResponse()
        }
        client.onStartScript { request in
            #expect(request.scriptName == "fixture")
            return try Self.scriptStartResponse()
        }
        client.onStopScript { request in
            #expect(request.scriptName == "fixture")
            return try Self.scriptStopResponse()
        }

        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))
        await store.refreshScripts(in: "w1")
        #expect(store.scripts(in: "w1").first?.lifecycle == .stopped)

        let started = await store.startScript("fixture", in: "w1")
        #expect(started?.lifecycle == .running)
        #expect(started?.terminalId?.isEmpty == false)
        #expect(store.scripts(in: "w1").first?.lifecycle == .running)

        let stopped = await store.stopScript("fixture", in: "w1")
        #expect(stopped?.lifecycle == .stopped)
        #expect(stopped?.exitCode == 0)
        #expect(store.scripts(in: "w1").first?.lifecycle == .stopped)
        #expect(store.error == nil)
    }

    @Test func scriptStatusUpdateReplacesTheSnapshot() async throws {
        let client = FakeDaemonClient()
        let store = TerminalsStore(client: client)
        await store.handle(connection: .connected(try Load.serverInfo()))

        let workspaceId = try scriptFixtureWorkspaceId()
        store.handle(
            messageType: "script_status_update",
            raw: try Fixture.terminalData("script_status_update_000", scenario: "scripts"))
        #expect(store.scripts(in: workspaceId).first?.lifecycle == .running)

        store.handle(
            messageType: "script_status_update",
            raw: try Fixture.terminalData("script_status_update_003", scenario: "scripts"))
        #expect(store.scripts(in: workspaceId).first?.lifecycle == .stopped)
    }

    // MARK: Helpers

    nonisolated private static func collect(_ stream: AsyncStream<TerminalOutput>) async -> [TerminalOutput] {
        var outputs: [TerminalOutput] = []
        for await output in stream { outputs.append(output) }
        return outputs
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

    nonisolated private static func killResponse() throws -> KillTerminalRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<KillTerminalRequest.Response>.self,
            from: Fixture.terminalData("kill_terminal_response")
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

    nonisolated private static func scriptStartResponse() throws -> StartWorkspaceScriptRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<StartWorkspaceScriptRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_start_response", scenario: "scripts")
        ).payload
    }

    nonisolated private static func scriptStopResponse() throws -> StopWorkspaceScriptRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<StopWorkspaceScriptRequest.Response>.self,
            from: Fixture.terminalData("workspace_script_stop_response", scenario: "scripts")
        ).payload
    }
}

// The captured script fixtures belong to the throwaway scripts workspace. Tests address it by the
// workspace id in the fixture itself, so no live id leaks into the suite's assumptions.
private func scriptFixtureWorkspaceId() throws -> String {
    try JSONDecoder().decode(
        SessionPayloadEnvelope<ScriptStatusUpdate>.self,
        from: Fixture.terminalData("script_status_update_000", scenario: "scripts")
    ).payload.workspaceId
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

extension FakeDaemonClient {
    func messages<M: PaseoOutboundMessage>(of type: M.Type) -> [M] {
        messages.compactMap { $0 as? M }
    }
}
