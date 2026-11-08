import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

private func subagentDescriptor(
    id: String = "sub-1", parent: String = "agent-1", status: String = "running"
) -> String {
    #"""
    {"id":"\#(id)","parentAgentId":"\#(parent)","provider":"claude","title":"Child",
     "description":"does work","status":"\#(status)",
     "createdAt":"2026-11-08T20:00:00Z","updatedAt":"2026-11-08T20:00:01Z",
     "toolCallId":"call-1","cwd":"/tmp/fixture-sandbox","subtitle":"2 tools"}
    """#
}

private func subagentUpdate(_ payload: String) -> Data {
    Data(#"{"type":"session","message":{"type":"agent.provider_subagents.update","payload":\#(payload)}}"#.utf8)
}

private func subagentListResponse(_ subagents: String) throws -> ProviderSubagentListRequest.Response {
    let json = #"""
        {"requestId":"r","parentAgentId":"agent-1","subagents":[\#(subagents)],"error":null}
        """#
    return try JSONDecoder().decode(
        ProviderSubagentListRequest.Response.self, from: Data(json.utf8))
}



/// T12: provider-managed subagents, list plus live update routing.
@Suite @MainActor
struct ConversationSubagentsTests {
    @Test func loadUsesTheParentAgentIdAndDecodesTheList() async throws {
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentListRequest.self) { _ in
            try subagentListResponse(subagentDescriptor())
        }
        let store = ConversationStore(agentId: "agent-1", client: client)

        await store.subagents.load()

        #expect(client.requests(ProviderSubagentListRequest.self).first?.parentAgentId == "agent-1")
        #expect(store.subagents.items.map(\.id) == ["sub-1"])
        #expect(store.subagents.active.count == 1)
        #expect(store.subagents.subagent(id: "sub-1")?.title == "Child")
        #expect(store.subagents.error == nil)
        #expect(!store.subagents.isLoading)
    }

    @Test func liveUpdatesUpsertInPlaceRemoveAndIgnoreOtherParents() {
        let store = ConversationStore(agentId: "agent-1", client: FakeDaemonClient())
        let running = subagentUpdate(#"{"kind":"upsert","subagent":\#(subagentDescriptor())}"#)
        let completed = subagentUpdate(
            #"{"kind":"upsert","subagent":\#(subagentDescriptor(status: "completed"))}"#)
        let otherParent = subagentUpdate(
            #"{"kind":"upsert","subagent":\#(subagentDescriptor(id: "sub-2", parent: "agent-2"))}"#)

        #expect(store.subagents.handle(messageType: "agent.provider_subagents.update", raw: running))
        #expect(store.subagents.items.map(\.id) == ["sub-1"])
        #expect(store.subagents.active.count == 1)

        _ = store.subagents.handle(
            messageType: "agent.provider_subagents.update", raw: completed)
        #expect(store.subagents.items.count == 1, "an upsert replaces in place")
        #expect(store.subagents.items.first?.status == .completed)
        #expect(store.subagents.active.isEmpty)

        _ = store.subagents.handle(
            messageType: "agent.provider_subagents.update", raw: otherParent)
        #expect(store.subagents.items.map(\.id) == ["sub-1"])

        let remove = subagentUpdate(#"{"kind":"remove","parentAgentId":"agent-1","subagentId":"sub-1"}"#)
        _ = store.subagents.handle(messageType: "agent.provider_subagents.update", raw: remove)
        #expect(store.subagents.items.isEmpty)
    }

    @Test func unrelatedMessageTypesAreNotConsumed() {
        let store = ConversationStore(agentId: "agent-1", client: FakeDaemonClient())
        #expect(
            !store.subagents.handle(
                messageType: "agent.provider_subagents.timeline.get.response", raw: Data("{}".utf8)))
    }

    @Test func hostSessionRoutesUpdatesToTheOpenConversation() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }

        let running = subagentUpdate(#"{"kind":"upsert","subagent":\#(subagentDescriptor(parent: agentId))}"#)
        client.push(.unhandled(messageType: "agent.provider_subagents.update", raw: running))

        let added = await eventually { store.subagents.items.map(\.id) == ["sub-1"] }
        #expect(added)

        let remove = subagentUpdate(#"{"kind":"remove","parentAgentId":"\#(agentId)","subagentId":"sub-1"}"#)
        client.push(.unhandled(messageType: "agent.provider_subagents.update", raw: remove))
        #expect(await eventually { store.subagents.items.isEmpty })
    }

    @Test func capabilityOffSkipsTheListAndTheUpdates() async throws {
        let client = FakeDaemonClient()
        var info = try Load.serverInfo()
        info.features = ["providerSubagents": .bool(false)]
        client.push(.connected(info))
        let agentId = try Load.fixtureAgentId()

        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        let store = session.conversation(for: agentId)
        #expect(!store.subagents.isSupported)

        await store.subagents.load()
        #expect(client.requests(ProviderSubagentListRequest.self).isEmpty)

        let running = subagentUpdate(#"{"kind":"upsert","subagent":\#(subagentDescriptor())}"#)
        #expect(!store.subagents.handle(messageType: "agent.provider_subagents.update", raw: running))
        #expect(store.subagents.items.isEmpty)
    }

    @Test func paseoSubagentsAreAgentsLabelledWithTheParent() async throws {
        let client = FakeDaemonClient()
        var agents = try Load.agents()
        agents.entries[0].agent.labels = ["paseo.parent-agent-id": "parent-1"]
        let original = try #require(agents.entries.first?.agent)
        let captured = agents
        client.onFetchAgents { _ in captured }

        let session = HostSession(client: client)
        await session.start()
        #expect(session.subagents(of: "parent-1").map(\.id) == [original.id])
        #expect(session.subagents(of: "parent-2").isEmpty)

        var child = original
        child.id = "child-1"
        child.labels = ["paseo.parent-agent-id": "parent-1"]
        client.push(.agentUpdate(.upsert(child, project: nil)))
        #expect(await eventually { session.subagents(of: "parent-1").count == 2 })
    }
}
