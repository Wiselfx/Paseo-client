import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

private struct FetchAgentEnvelope: Decodable {
    struct Message: Decodable {
        struct Payload: Decodable { let agent: AgentSnapshot? }
        let payload: Payload
    }
    let message: Message
}

/// Rewind (M7d): capability flags decoded verbatim from a live sandbox snapshot, the correlated
/// `agent.rewind.response` payload, the host feature gate and the store's error paths.
@Suite @MainActor
struct RewindTests {
    private let decoder = JSONDecoder()

    private func rewindFixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "rewind")
    }

    private func serverInfo() throws -> ServerInfo {
        try decoder.decode(
            SessionPayloadEnvelope<ServerInfo>.self, from: rewindFixture("server_info")).payload
    }

    private func fetchedAgent() throws -> AgentSnapshot {
        let envelope = try decoder.decode(
            FetchAgentEnvelope.self, from: rewindFixture("fetch_agent_response"))
        return try #require(envelope.message.payload.agent)
    }

    @Test func serverInfoFixtureAdvertisesRewind() throws {
        let info = try serverInfo()
        #expect(info.hasFeature("rewind"))
    }

    @Test func fetchAgentFixtureCarriesProviderCapabilityFlags() throws {
        let agent = try fetchedAgent()
        let flags = try #require(agent.capabilities)
        // The sandbox provider (opencode) advertises `both` only; both flags decode verbatim.
        #expect(flags.supportsRewindBoth)
        #expect(!flags.supportsRewindConversation)
        #expect(!flags.supportsRewindFiles)
    }

    @Test func rewindTimelineFixtureDecodesProjectedEntries() throws {
        let page = try decoder.decode(
            SessionPayloadEnvelope<FetchAgentTimelineRequest.Response>.self,
            from: rewindFixture("fetch_agent_timeline_before")).payload
        #expect(page.entries.count == 23)
        #expect(page.entries.allSatisfy { $0.seqStart <= $0.seqEnd })
        let userMessages = page.entries.filter {
            if case .userMessage = $0.item { return true } else { return false }
        }
        #expect(!userMessages.isEmpty)
        #expect(
            userMessages.allSatisfy { entry in
                if case .userMessage(let message) = entry.item {
                    return message.messageId != nil
                }
                return false
            })
    }

    @Test func okResponseFixtureDecodes() throws {
        let response = try decoder.decode(
            SessionPayloadEnvelope<RewindAgentRequest.Response>.self,
            from: rewindFixture("agent_rewind_response")).payload
        #expect(response.ok)
        #expect(response.error == nil)
        #expect(response.requestId == "rewind-request")
    }

    @Test func refusalResponseFixtureDecodesVerbatim() throws {
        let response = try decoder.decode(
            SessionPayloadEnvelope<RewindAgentRequest.Response>.self,
            from: rewindFixture("agent_rewind_response_conversation_unsupported")).payload
        #expect(!response.ok)
        #expect(response.error == "Provider does not support rewinding conversation")
    }

    @Test func capabilitiesMenuFollowsAdvertisedFlags() throws {
        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: FakeDaemonClient())
        // No snapshot yet: nothing advertised, affordance hidden.
        #expect(!store.rewindCapabilities.isAvailable)
        #expect(store.rewindCapabilities.menu.isEmpty)

        store.applyAgent(agent)
        #expect(store.rewindCapabilities.isAvailable)
        #expect(store.rewindCapabilities.menu == [.both])
    }

    @Test func rewindSendsTheRequestAndSucceeds() async throws {
        let client = FakeDaemonClient()
        let ok = try decoder.decode(
            SessionPayloadEnvelope<RewindAgentRequest.Response>.self,
            from: rewindFixture("agent_rewind_response")).payload
        client.onSend(RewindAgentRequest.self) { _ in ok }

        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)
        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == nil)
        let request = try #require(client.requests(RewindAgentRequest.self).first)
        #expect(request.agentId == agent.id)
        #expect(request.messageId == "rewind-fixture-probe-1")
        #expect(request.mode == .both)
    }

    @Test func rewindSurfacesProviderRefusal() async throws {
        let client = FakeDaemonClient()
        let refusal = try decoder.decode(
            SessionPayloadEnvelope<RewindAgentRequest.Response>.self,
            from: rewindFixture("agent_rewind_response_conversation_unsupported")).payload
        client.onSend(RewindAgentRequest.self) { _ in refusal }

        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)
        // `both` is advertised by the sandbox snapshot, so the request rides the wire and the
        // provider's refusal surfaces verbatim.
        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == "Provider does not support rewinding conversation")
    }

    @Test func rewindRefusesUnsupportedScopesWithoutAWireRoundTrip() async throws {
        let client = FakeDaemonClient()
        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        // The snapshot advertises `both` only; a `conversation` rewind is refused client-side.
        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .conversation)

        #expect(failure == "This provider does not support rewinding that scope.")
        #expect(client.requests(RewindAgentRequest.self).isEmpty)
    }

    @Test func rewindSurfacesTransportFailure() async throws {
        struct Boom: Error {}
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in throw Boom() }

        let store = ConversationStore(agentId: "agent-1", client: client)
        // Snapshot advertises every scope, so the wire path is reached.
        store.applyAgent(try allScopesSnapshot())
        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .conversation)

        #expect(failure != nil)
    }

    @Test func hostGateRequiresConnectedServerInfo() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        let session = HostSession(client: client)
        await session.start()
        // Connected but not started through a state push yet: the gate must not open.
        #expect(!session.isRewindSupportedByHost)

        client.push(.connected(try serverInfo()))
        let opened = await eventually { session.serverInfo != nil }
        #expect(opened)
        #expect(session.isRewindSupportedByHost)
    }

    /// The sandbox snapshot with every scope advertised, for the transport-failure path.
    private func allScopesSnapshot() throws -> AgentSnapshot {
        var agent = try fetchedAgent()
        if var flags = agent.capabilities {
            flags.supportsRewindConversation = true
            agent.capabilities = flags
        }
        return agent
    }
}
