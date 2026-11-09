import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// B8: detaching a managed subagent (`agent.detach.request`). Upstream
/// `subagents/detach-subagent.ts`: confirm → `detachAgent` → open the agent; a rejection is
/// reported, not retried.
@Suite @MainActor
struct AgentDetachTests {
    private func historyEntry() throws -> FetchAgentHistoryRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentHistoryRequest.Response>.self,
            from: Fixture.data("history_page2", in: "agent-lifecycle")
        ).payload
    }

    /// The fixture agent, wearing the parent labels a managed subagent carries.
    private func childPage(_ parentId: String) throws -> FetchAgentHistoryRequest.Response {
        var page = try historyEntry()
        page.entries[0].agent.archivedAt = nil
        page.entries[0].agent.labels = [
            AgentParentLabel.agentId: parentId,
            AgentParentLabel.serverId: "server-1",
        ]
        return page
    }

    private func actionResponse(accepted: Bool, error: String?) throws -> AgentActionResponse {
        let errorJSON = error.map { #""\#($0)""# } ?? "null"
        let json = #"{"requestId":"r-1","agentId":"a-1","accepted":\#(accepted),"error":\#(errorJSON)}"#
        return try JSONDecoder().decode(AgentActionResponse.self, from: Data(json.utf8))
    }

    @Test func detachSendsTheNamespacedRequestAndDropsTheParentLabel() async throws {
        let page = try childPage("parent-1")
        let agentId = try #require(page.entries.first?.agent.id)
        let accepted = try actionResponse(accepted: true, error: nil)
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(AgentDetachRequest.self) { _ in accepted }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        #expect(store.entries.first?.labels?[AgentParentLabel.agentId] == "parent-1")

        let ok = await store.detach(agentId: agentId)

        #expect(ok)
        let sent = try #require(client.requests(AgentDetachRequest.self).first)
        #expect(sent.agentId == agentId)
        #expect(store.entries.first?.labels?[AgentParentLabel.agentId] == nil)
        #expect(store.actionError == nil)
        #expect(!store.isWorking)
    }

    @Test func rejectedDetachKeepsTheLabelAndReportsTheError() async throws {
        let page = try childPage("parent-1")
        let agentId = try #require(page.entries.first?.agent.id)
        let rejected = try actionResponse(accepted: false, error: "This host cannot detach agents.")
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(AgentDetachRequest.self) { _ in rejected }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        let ok = await store.detach(agentId: agentId)

        #expect(!ok)
        #expect(store.actionError == "This host cannot detach agents.")
        #expect(store.entries.first?.labels?[AgentParentLabel.agentId] == "parent-1")
    }

    @Test func transportFailureIsReportedAndLeavesTheLabel() async throws {
        let page = try childPage("parent-1")
        let agentId = try #require(page.entries.first?.agent.id)
        let client = FakeDaemonClient()
        client.on(FetchAgentHistoryRequest.self) { _ in page }
        client.on(AgentDetachRequest.self) { _ in
            throw FakeDaemonClient.FakeError.unexpectedResponse(AgentDetachRequest.type)
        }
        let store = AgentLifecycleStore(client: client)

        await store.load()
        let ok = await store.detach(agentId: agentId)

        #expect(!ok)
        #expect(store.actionError != nil)
        #expect(store.entries.first?.labels?[AgentParentLabel.agentId] == "parent-1")
    }

    // MARK: Parent labels

    @Test func parentLabelIgnoresBlankAndMissingValues() {
        #expect(AgentParentLabel.parent(of: nil) == nil)
        #expect(AgentParentLabel.parent(of: [:]) == nil)
        #expect(AgentParentLabel.parent(of: [AgentParentLabel.agentId: "   "]) == nil)
        #expect(AgentParentLabel.parent(of: [AgentParentLabel.agentId: " parent-1\n"]) == "parent-1")
    }

    @Test func parentServerFallsBackToTheLocalHost() {
        #expect(AgentParentLabel.parentServer(of: nil, defaultingTo: "local") == "local")
        #expect(
            AgentParentLabel.parentServer(
                of: [AgentParentLabel.serverId: " "], defaultingTo: "local") == "local")
        #expect(
            AgentParentLabel.parentServer(
                of: [AgentParentLabel.serverId: "remote"], defaultingTo: "local") == "remote")
    }

    @Test func managedSubagentsAreAgentsLabelledWithTheParent() async throws {
        var page = try Load.agents()
        let child = try #require(page.entries.first?.agent.id)
        page.entries[0].agent.labels = [AgentParentLabel.agentId: "parent-1"]
        let agents = page
        let client = FakeDaemonClient()
        let session = HostSession(client: client)
        client.on(FetchAgentsRequest.self) { _ in agents }

        await session.refreshAgents()

        #expect(session.subagents(of: "parent-1").map(\.id) == [child])
        #expect(session.subagents(of: "parent-2").isEmpty)
    }
}
