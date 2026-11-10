import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// R3 §3: pushed subagent and background-work updates are decoded once in `HostSession` and routed
/// only to the conversation they belong to.
@Suite @MainActor
struct PushedUpdateRoutingTests {
    private nonisolated static func emptyAgents() throws -> Data {
        Data(#"{"requestId":"r","entries":[]}"#.utf8)
    }

    private nonisolated static func gateServerInfo(
        work: Bool, stop: Bool = false
    ) throws -> ServerInfo {
        let json = """
        {"serverId":"srv_FIXTURE","version":"0.15.2","features":{
          "agentBackgroundWork":\(work),"agentBackgroundWorkStop":\(stop)
        }}
        """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    private nonisolated static func frame(_ messageType: String, _ payload: String) -> Data {
        Data(#"{"type":"session","message":{"type":"\#(messageType)","payload":\#(payload)}}"#.utf8)
    }

    private nonisolated static func subagent(
        id: String = "sub-1", parent: String = "agent-1", status: String = "running"
    ) -> String {
        #"""
        {"id":"\#(id)","parentAgentId":"\#(parent)","provider":"claude","title":"Child",
         "status":"\#(status)","createdAt":"2026-11-08T20:00:00Z",
         "updatedAt":"2026-11-08T20:00:01Z","cwd":"/tmp/fixture-sandbox"}
        """#
    }

    private func startedSession() async throws -> (FakeDaemonClient, HostSession) {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in
            try JSONDecoder().decode(
                FetchAgentsRequest.Response.self, from: try Self.emptyAgents())
        }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        let session = HostSession(client: client)
        await session.start()
        return (client, session)
    }

    private func openConversations(
        _ session: HostSession, _ ids: [String]
    ) async throws -> [ConversationStore] {
        let stores = ids.map { session.conversation(for: $0) }
        let ready = await eventually { stores.allSatisfy { $0.phase == .ready } }
        #expect(ready)
        return stores
    }

    @Test func aSubagentUpdateReachesOnlyItsParentConversation() async throws {
        let (client, session) = try await startedSession()
        let stores = try await openConversations(session, ["agent-1", "agent-2"])
        let first = stores[0]
        let second = stores[1]

        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update",
                    #"{"kind":"upsert","subagent":\#(Self.subagent())}"#)))
        let applied = await eventually { first.subagents.items.map(\.id) == ["sub-1"] }
        #expect(applied)
        #expect(second.subagents.items.isEmpty, "the other conversation never applied it")

        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update",
                    #"{"kind":"remove","parentAgentId":"agent-1","subagentId":"sub-1"}"#)))
        let removed = await eventually { first.subagents.items.isEmpty }
        #expect(removed)
        #expect(second.subagents.items.isEmpty)
    }

    @Test func aBackgroundWorkUpdateReachesOnlyItsAgent() async throws {
        let (client, session) = try await startedSession()
        let stores = try await openConversations(session, ["agent-1", "agent-2"])
        let first = stores[0]
        let second = stores[1]
        // The gate is off until the daemon says it supports background work.
        client.push(.connected(try Self.gateServerInfo(work: true)))
        let connected = await eventually { session.serverInfo != nil }
        #expect(connected)

        let item = #"""
            {"id":"bg-1","kind":"shell","description":"watch","command":"npm run watch",
             "startedAt":"2026-11-09T07:40:00.000Z","canStop":true,"stopToken":"tok"}
            """#
        client.push(
            .unhandled(
                messageType: "agent.background_work.update",
                raw: Self.frame(
                    "agent.background_work.update",
                    #"{"agentId":"agent-1","items":[\#(item)]}"#)))
        let applied = await eventually { first.backgroundWork.items.map(\.id) == ["bg-1"] }
        #expect(applied)
        #expect(second.backgroundWork.items.isEmpty, "the other conversation never applied it")
    }

    @Test func anUpdateForAnUnopenedParentTouchesNoConversation() async throws {
        let (client, session) = try await startedSession()
        let stores = try await openConversations(session, ["agent-1"])
        let open = stores[0]

        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update",
                    #"{"kind":"upsert","subagent":\#(Self.subagent(parent: "agent-closed"))}"#)))
        // A later subagent update for the open conversation proves the first one was processed.
        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update",
                    #"{"kind":"upsert","subagent":\#(Self.subagent(id: "sub-2"))}"#)))
        let applied = await eventually { open.subagents.items.map(\.id) == ["sub-2"] }
        #expect(applied)

        // A payload the routing cannot attribute (no known kind) is offered to every conversation,
        // which changes nothing and must not crash.
        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update", #"{"kind":"future_kind"}"#)))
        client.push(
            .unhandled(
                messageType: "agent.provider_subagents.update",
                raw: Self.frame(
                    "agent.provider_subagents.update",
                    #"{"kind":"upsert","subagent":\#(Self.subagent(id: "sub-3"))}"#)))
        let stillApplied = await eventually { open.subagents.items.map(\.id) == ["sub-2", "sub-3"] }
        #expect(stillApplied)
    }
}
