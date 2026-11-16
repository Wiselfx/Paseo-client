import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M7g: background shells/monitors — gate handling, list/stop RPCs, live updates.
/// The sandbox daemon (v0.15.2) does not advertise `features.agentBackgroundWork` and answers
/// with `rpc_error` / `unknown_schema` (captured in `background-work/`), so the populated list
/// and stop flows are covered with synthetic pages from the documented wire shape
/// (messages.ts `AgentBackgroundWorkItemSchema`, messages.ts:5047).
@Suite @MainActor
struct BackgroundWorkStoreTests {
    private nonisolated static func fixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "background-work")
    }

    private nonisolated static func gateServerInfo(work: Bool, stop: Bool = false) throws
        -> ServerInfo
    {
        let json = """
        {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
          "agentBackgroundWork":\(work),"agentBackgroundWorkStop":\(stop)
        }}
        """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    private nonisolated static func itemsPage(_ items: String) throws
        -> BackgroundWorkListRequest.Response
    {
        let json = """
        {"type":"session","message":{"type":"agent.background_work.list.response",
          "payload":{"requestId":"bg-list","agentId":"agent-1","items":[\(items)],"error":null}}}
        """
        return try JSONDecoder().decode(
            SessionPayloadEnvelope<BackgroundWorkListRequest.Response>.self,
            from: Data(json.utf8)).payload
    }

    private nonisolated static func shellItem(
        id: String, canStop: Bool? = true, stopToken: String? = "tok-shared",
        kind: String = "shell"
    ) -> String {
        let canStopValue = canStop.map { $0 ? "true" : "false" } ?? "null"
        let tokenValue = stopToken.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","kind":"\(kind)","description":"watch the build",
         "command":"npm run watch","startedAt":"2026-11-09T07:40:00.000Z",
         "canStop":\(canStopValue),"stopToken":\(tokenValue)}
        """
    }

    @Test func serverInfoFixtureDoesNotAdvertiseTheGate() throws {
        let info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self, from: Self.fixture("server_info")).payload
        #expect(!info.hasFeature("agentBackgroundWork"))
        #expect(!info.hasFeature("agentBackgroundWorkStop"))
    }

    @Test func unknownSchemaRefusalDecodesTolerantly() throws {
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<BackgroundWorkListRequest.Response>.self,
            from: Self.fixture("agent_background_work_list_unknown_schema")).payload
        // The refusal is an rpc_error without items/agentId; the tolerant decode must not throw.
        #expect(response.items.isEmpty)
        #expect(response.error == "Unknown request, try upgrading the daemon (currently v0.15.2)")
    }

    @Test func loadPopulatesItemsWhenTheGateIsOn() async throws {
        let client = FakeDaemonClient()
        client.onSend(BackgroundWorkListRequest.self) { _ in
            try Self.itemsPage(
                "\(Self.shellItem(id: "bg-1")),\(Self.shellItem(id: "bg-2", kind: "monitor"))")
        }
        let store = BackgroundWorkStore(agentId: "agent-1", client: client)
        store.update(serverInfo: try Self.gateServerInfo(work: true, stop: true))
        await store.load()

        #expect(store.isSupported)
        #expect(store.canStop)
        #expect(store.items.map(\.id) == ["bg-1", "bg-2"])
        #expect(store.items[1].kind == "monitor")
        #expect(store.error == nil)
        #expect(store.hasRunningItems)
    }

    @Test func loadIsANoOpWithoutTheGate() async throws {
        let client = FakeDaemonClient()
        client.onSend(BackgroundWorkListRequest.self) { _ in
            try Self.itemsPage(Self.shellItem(id: "bg-1"))
        }
        let store = BackgroundWorkStore(agentId: "agent-1", client: client)
        store.update(serverInfo: try Self.gateServerInfo(work: true))
        await store.load()
        #expect(store.items.count == 1)

        // The gate drops on the next server_info: the list clears and no further RPC rides out.
        store.update(serverInfo: try Self.gateServerInfo(work: false))
        let sent = client.requests(BackgroundWorkListRequest.self).count
        await store.load()
        #expect(!store.isSupported)
        #expect(store.items.isEmpty)
        #expect(client.requests(BackgroundWorkListRequest.self).count == sent)
    }

    @Test func listFailureSurfacesTheDaemonMessage() async throws {
        let client = FakeDaemonClient()
        client.onSend(BackgroundWorkListRequest.self) { _ in
            let decoded = try JSONDecoder().decode(
                SessionPayloadEnvelope<BackgroundWorkListRequest.Response>.self,
                from: Self.fixture("agent_background_work_list_unknown_schema"))
            return decoded.payload
        }
        let store = BackgroundWorkStore(agentId: "agent-1", client: client)
        store.update(serverInfo: try Self.gateServerInfo(work: true))
        await store.load()

        #expect(store.items.isEmpty)
        #expect(store.error == "Unknown request, try upgrading the daemon (currently v0.15.2)")
    }

    @Test func stopSendsTokenAndRemovesTheItemOptimistically() async throws {
        let token = "tok-stop-1"
        let client = FakeDaemonClient()
        client.onSend(BackgroundWorkListRequest.self) { _ in
            try Self.itemsPage(Self.shellItem(id: "bg-1", canStop: true, stopToken: token))
        }
        client.onSend(BackgroundWorkStopRequest.self) { _ in
            let json = """
            {"type":"session","message":{"type":"agent.background_work.stop.response",
              "payload":{"requestId":"bg-stop","agentId":"agent-1","itemId":"bg-1","error":null}}}
            """
            return try JSONDecoder().decode(
                SessionPayloadEnvelope<BackgroundWorkStopRequest.Response>.self,
                from: Data(json.utf8)).payload
        }
        let store = BackgroundWorkStore(agentId: "agent-1", client: client)
        store.update(serverInfo: try Self.gateServerInfo(work: true, stop: true))
        await store.load()
        #expect(store.items.count == 1)

        let refusal = await store.stop(itemId: "bg-1")
        #expect(refusal == nil)
        #expect(store.items.isEmpty)
        let request = try #require(client.requests(BackgroundWorkStopRequest.self).first)
        #expect(request.itemId == "bg-1")
        #expect(request.stopToken == token)
    }

    @Test func stopRefusesWithoutTheStopGateOrItemToken() async throws {
        let client = FakeDaemonClient()
        client.onSend(BackgroundWorkListRequest.self) { _ in
            try Self.itemsPage(Self.shellItem(id: "bg-1", canStop: false, stopToken: nil))
        }
        let store = BackgroundWorkStore(agentId: "agent-1", client: client)
        store.update(serverInfo: try Self.gateServerInfo(work: true, stop: false))
        await store.load()

        // Stop gate off: nothing rides the wire.
        let gateRefusal = await store.stop(itemId: "bg-1")
        #expect(gateRefusal == "Background work stop is not supported on this host.")

        // Stop gate on but the provider says no: token/canStop rules win.
        store.update(serverInfo: try Self.gateServerInfo(work: true, stop: true))
        let itemRefusal = await store.stop(itemId: "bg-1")
        #expect(itemRefusal == "This task can't be stopped.")
        #expect(client.requests(BackgroundWorkStopRequest.self).isEmpty)
    }

    @Test func updateEventReplacesTheWholeList() async throws {
        let store = BackgroundWorkStore(agentId: "agent-1", client: FakeDaemonClient())
        store.update(serverInfo: try Self.gateServerInfo(work: true))

        let raw = Data("""
        {"type":"session","message":{"type":"agent.background_work.update",
          "payload":{"agentId":"agent-1","items":[\(Self.shellItem(id: "bg-7"))]}}}
        """.utf8)
        let routed = store.handle(messageType: "agent.background_work.update", raw: raw)

        #expect(routed)
        #expect(store.items.map(\.id) == ["bg-7"])
        #expect(store.error == nil)
    }

    @Test func updateEventIgnoresOtherAgents() throws {
        let store = BackgroundWorkStore(agentId: "agent-1", client: FakeDaemonClient())
        store.update(serverInfo: try Self.gateServerInfo(work: true))

        let raw = Data("""
        {"type":"session","message":{"type":"agent.background_work.update",
          "payload":{"agentId":"agent-2","items":[\(Self.shellItem(id: "bg-9"))]}}}
        """.utf8)
        let routed = store.handle(messageType: "agent.background_work.update", raw: raw)

        #expect(routed)
        #expect(store.items.isEmpty)
    }

    @Test func updateEventIsUnroutableWithoutTheGate() throws {
        let store = BackgroundWorkStore(agentId: "agent-1", client: FakeDaemonClient())
        // Gate off: the raw message is left for the fallback path, not consumed.
        let raw = Data("""
        {"type":"session","message":{"type":"agent.background_work.update",
          "payload":{"agentId":"agent-1","items":[]}}}
        """.utf8)
        #expect(!store.handle(messageType: "agent.background_work.update", raw: raw))
    }
}
