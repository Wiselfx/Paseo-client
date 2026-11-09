import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M7h: fork the conversation into a new agent. Fixtures are a real capture from the sandbox —
/// `fixtures/fork/` (throwaways created and archived by the capture), ids scrubbed to
/// fork-fixture-*. The main timeline page/subscription come from the shared rewind-area
/// fixtures.
@Suite @MainActor
struct ForkTests {
    private nonisolated static func forkFixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "fork")
    }

    private nonisolated static func serverInfo() throws -> ServerInfo {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self, from: Self.forkFixture("server_info")).payload
    }

    private nonisolated static func forkContext() throws -> ForkContextRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<ForkContextRequest.Response>.self,
            from: Self.forkFixture("agent_fork_context_response")).payload
    }

    private nonisolated static func createdFork() throws -> CreateAgentRequest.Response {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<CreateAgentRequest.Response>.self,
            from: Self.forkFixture("create_fork_response")).payload
    }

    @Test func serverInfoFixtureAdvertisesForkContext() throws {
        #expect(try Self.serverInfo().hasFeature("agentForkContext"))
    }

    @Test func forkContextResponseDecodesVerbatim() throws {
        let response = try Self.forkContext()

        #expect(response.error == nil)
        #expect(response.itemCount == 2)
        let attachment = try #require(response.attachment)
        #expect(attachment.contextKind == "chat_history")
        #expect(attachment.title == "Chat history")
        #expect(!attachment.text.isEmpty)
        #expect(response.boundaryCursor?.seq == 2)
    }

    @Test func forkSendsTheCursorAndSeedsTheNewAgent() async throws {
        let agents = try Load.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        let page = try Load.page()
        let subscription = try Load.subscription()
        let forkContext = try Self.forkContext()
        let createdFork = try Self.createdFork()

        let client = FakeDaemonClient()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in page }
        client.onSetSubscription { _ in subscription }
        client.onSend(ForkContextRequest.self) { _ in forkContext }
        client.onSend(CreateAgentRequest.self) { _ in createdFork }

        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Self.serverInfo()))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        #expect(session.isForkContextSupportedByHost)

        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)

        let result = await store.forkConversation(fromBoundarySeq: 42)

        #expect(result.error == nil)
        #expect(result.agentId == createdFork.agent?.id)

        let forkRequest = try #require(client.requests(ForkContextRequest.self).first)
        #expect(forkRequest.agentId == agentId)
        #expect(forkRequest.boundaryCursor?.epoch == page.epoch)
        #expect(forkRequest.boundaryCursor?.seq == 42)

        let createRequest = try #require(client.requests(CreateAgentRequest.self).first)
        #expect(createRequest.initialPrompt == nil)
        #expect(createRequest.workspaceId == agents.entries.first?.agent.workspaceId)
        let createdAttachment = try #require(createRequest.attachments?.first)
        guard case .text(let attachment) = createdAttachment else {
            Issue.record("expected the fork seed text attachment")
            return
        }
        #expect(attachment.contextKind == "chat_history")
        #expect(attachment.text == forkContext.attachment?.text)
    }

    @Test func forkRefusesToCreateWithoutTheCreateResponse() async throws {
        let agents = try Load.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        let page = try Load.page()
        let subscription = try Load.subscription()

        let client = FakeDaemonClient()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in page }
        client.onSetSubscription { _ in subscription }
        client.onSend(ForkContextRequest.self) { _ in
            var response = try Self.forkContext()
            response.attachment = nil
            return response
        }

        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Self.serverInfo()))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)

        let result = await store.forkConversation(fromBoundarySeq: 42)
        #expect(result.agentId == nil)
        #expect(result.error == "Fork returned no chat history.")
        #expect(client.requests(CreateAgentRequest.self).isEmpty)
    }

    @Test func forkContextErrorSurfaces() async throws {
        let agents = try Load.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        let page = try Load.page()
        let subscription = try Load.subscription()

        let client = FakeDaemonClient()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in page }
        client.onSetSubscription { _ in subscription }
        client.onSend(ForkContextRequest.self) { _ in
            var response = try Self.forkContext()
            response.attachment = nil
            response.error = "Selected timeline position is no longer available."
            return response
        }

        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Self.serverInfo()))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)

        let result = await store.forkConversation(fromBoundarySeq: 42)
        #expect(result.agentId == nil)
        #expect(result.error == "Selected timeline position is no longer available.")
    }

    @Test func hostGateDefaultsToClosedWithoutForkFeature() async throws {
        let json = """
        {"serverId":"srv_FIXTURE","version":"0.15.2","features":{"agentForkContext":false}}
        """
        let info = try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(info))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        #expect(!session.isForkContextSupportedByHost)
    }

    @Test func createAgentRequestEncodesAttachmentsFlat() throws {
        let request = CreateAgentRequest(
            config: AgentSessionConfig(provider: "opencode", cwd: "/tmp/fixture-sandbox"),
            attachments: [
                .text(
                    AgentAttachment.TextAttachment(
                        text: "seed", title: "Chat history", contextKind: "chat_history"))
            ])
        let data = try JSONEncoder().encode(request)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachments = try #require(object["attachments"] as? [[String: Any]])
        let first = try #require(attachments.first)
        #expect(first["type"] as? String == "text")
        #expect(first["contextKind"] as? String == "chat_history")
        #expect(first["text"] as? String == "seed")
    }
}
