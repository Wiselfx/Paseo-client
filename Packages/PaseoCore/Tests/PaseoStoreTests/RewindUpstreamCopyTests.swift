import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// L1: rewind failure copy is upstream's (en.ts), and a rewind that changes the conversation
/// refetches the timeline the way upstream's mutation does (use-rewind-agent-mutation.ts:38-49).
@Suite @MainActor
struct RewindUpstreamCopyTests {
    private let decoder = JSONDecoder()

    private func rewindFixture(_ name: String) throws -> Data {
        try Fixture.data(name, in: "rewind")
    }

    private func fetchedAgent() throws -> AgentSnapshot {
        struct Envelope: Decodable {
            struct Message: Decodable {
                struct Payload: Decodable { let agent: AgentSnapshot? }
                let payload: Payload
            }
            let message: Message
        }
        let envelope = try decoder.decode(
            Envelope.self, from: rewindFixture("fetch_agent_response"))
        return try #require(envelope.message.payload.agent)
    }

    /// The sandbox snapshot with every scope advertised, so the wire path is reached for each.
    private func allScopesSnapshot() throws -> AgentSnapshot {
        var agent = try fetchedAgent()
        if var flags = agent.capabilities {
            flags.supportsRewindConversation = true
            flags.supportsRewindFiles = true
            agent.capabilities = flags
        }
        return agent
    }

    private func timelinePage() throws -> FetchAgentTimelineRequest.Response {
        try decoder.decode(
            SessionPayloadEnvelope<FetchAgentTimelineRequest.Response>.self,
            from: rewindFixture("fetch_agent_timeline_before")).payload
    }

    // MARK: Failure copy (upstream en.ts)

    @Test func refusalWithoutReasonUsesUpstreamFailedCopy() async throws {
        // Upstream rewind.errors.failed, en.ts:2019.
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in
            try decodeRefusal(#"{"ok": false}"#)
        }
        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == "Failed to rewind agent")
    }

    @Test func refusalWithReasonStillSurfacesTheReasonVerbatim() async throws {
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in
            try decodeRefusal(#"{"ok": false, "error": "Nope"}"#)
        }
        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == "Nope")
    }

    @Test func missingClientUsesUpstreamUnavailableCopy() async throws {
        // Upstream common.errors.daemonClientUnavailable, en.ts:68.
        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == "Daemon client unavailable")
    }

    // MARK: Timeline refetch (use-rewind-agent-mutation.ts:38-49)

    @Test func conversationRewindRefetchesTheTimeline() async throws {
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in try decodeRefusal(#"{"ok": true}"#) }
        let page = try timelinePage()
        client.onFetchTimeline { _ in page }

        let agent = try allScopesSnapshot()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .conversation)

        #expect(failure == nil)
        #expect(client.requests(RewindAgentRequest.self).count == 1)
        #expect(!client.requests(FetchAgentTimelineRequest.self).isEmpty)
    }

    @Test func bothRewindRefetchesTheTimeline() async throws {
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in try decodeRefusal(#"{"ok": true}"#) }
        let page = try timelinePage()
        client.onFetchTimeline { _ in page }

        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(failure == nil)
        #expect(!client.requests(FetchAgentTimelineRequest.self).isEmpty)
    }

    @Test func filesRewindDoesNotRefetchTheTimeline() async throws {
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in try decodeRefusal(#"{"ok": true}"#) }
        let page = try timelinePage()
        client.onFetchTimeline { _ in page }

        let agent = try allScopesSnapshot()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        let failure = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .files)

        #expect(failure == nil)
        #expect(client.requests(RewindAgentRequest.self).count == 1)
        #expect(client.requests(FetchAgentTimelineRequest.self).isEmpty)
    }

    @Test func refusedRewindDoesNotRefetchTheTimeline() async throws {
        let client = FakeDaemonClient()
        client.onSend(RewindAgentRequest.self) { _ in try decodeRefusal(#"{"ok": false}"#) }
        let page = try timelinePage()
        client.onFetchTimeline { _ in page }

        let agent = try fetchedAgent()
        let store = ConversationStore(agentId: agent.id, client: client)
        store.applyAgent(agent)

        _ = await store.rewind(toMessageId: "rewind-fixture-probe-1", scope: .both)

        #expect(client.requests(FetchAgentTimelineRequest.self).isEmpty)
    }
}

/// Decodes a `agent.rewind.response` payload, for the fake daemon's replies.
private func decodeRefusal(_ json: String) throws -> RewindAgentRequest.Response {
    try JSONDecoder().decode(RewindAgentRequest.Response.self, from: Data(json.utf8))
}
