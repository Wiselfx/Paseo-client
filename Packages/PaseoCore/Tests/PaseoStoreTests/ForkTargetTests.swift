import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// V1: fork target choice and the in-flight fork. The fork itself is `ForkTests`; these guard the
/// two new knobs — no boundary (whole timeline, for a running turn) and an explicit target
/// workspace (fork into a workspace created for the fork).
@Suite @MainActor
struct ForkTargetTests {
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

    @MainActor
    private static func readySession(
        forkContext: ForkContextRequest.Response
    ) async throws -> (HostSession, ConversationStore, FakeDaemonClient, String) {
        let agents = try Load.agents()
        let agentId = try #require(agents.entries.first?.agent.id)
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSend(ForkContextRequest.self) { _ in forkContext }
        client.onSend(CreateAgentRequest.self) { _ in try JSONDecoder().decode(
            SessionPayloadEnvelope<CreateAgentRequest.Response>.self,
            from: try Self.forkFixture("create_fork_response")).payload }

        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Self.serverInfo()))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        return (session, store, client, agentId)
    }

    @Test func inFlightForkSendsNoBoundary() async throws {
        // Upstream `turn-footer.tsx:38-46`: the running turn's forker deliberately omits the
        // boundary so the daemon projects the whole timeline, live answer included.
        let (_, store, client, agentId) = try await Self.readySession(
            forkContext: try Self.forkContext())

        let result = await store.forkConversation(fromBoundarySeq: nil)

        #expect(result.error == nil)
        let request = try #require(client.requests(ForkContextRequest.self).first)
        #expect(request.agentId == agentId)
        #expect(request.boundaryCursor == nil)
        #expect(request.boundaryMessageId == nil)

        // And on the wire: absent, not null. The daemon keys off the field being missing.
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["boundaryCursor"] == nil)
        #expect(object["boundaryMessageId"] == nil)
    }

    @Test func forkIntoAnExplicitWorkspaceCreatesTheAgentThere() async throws {
        let forkContext = try Self.forkContext()
        let (_, store, client, _) = try await Self.readySession(forkContext: forkContext)

        let result = await store.forkConversation(
            fromBoundarySeq: 42, into: "ws_fork_target")

        #expect(result.error == nil)
        let createRequest = try #require(client.requests(CreateAgentRequest.self).first)
        #expect(createRequest.workspaceId == "ws_fork_target")
        // The boundary still pins to the row the user chose.
        let forkRequest = try #require(client.requests(ForkContextRequest.self).first)
        #expect(forkRequest.boundaryCursor?.seq == 42)
    }
}
