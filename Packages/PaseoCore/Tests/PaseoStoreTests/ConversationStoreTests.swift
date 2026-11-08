import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct ConversationStoreTests {
    @Test func streamingAppendsToTheOpenConversation() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { request in
            request.direction == .tail ? try Load.page(before: 8) : try Load.page()
        }
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        let ready = await eventually { store.phase == .ready }
        #expect(ready)
        #expect(store.timeline.rows.count == 3)

        for payload in try Load.stream() {
            client.push(.agentStream(payload))
        }

        let streamed = await eventually { store.turns.count == 2 && store.activeTurnId == nil }
        #expect(streamed)
        #expect(store.turns.count == 2)
        #expect(store.activeTurnId == nil, "turn_completed clears the active turn")

        let turn = try #require(store.turns.last)
        let lastSegment = try #require(turn.segments.last)
        guard case .prose(let prose) = lastSegment else {
            Issue.record("second turn should end with prose, got \(lastSegment)")
            return
        }
        guard case .assistantMessage(let message) = prose.item else {
            Issue.record("prose row should be an assistant message")
            return
        }

        var expected: String?
        for entry in try Load.page().entries where entry.seqStart == 18 {
            if case .assistantMessage(let projected) = entry.item { expected = projected.text }
        }
        #expect(message.text == (try #require(expected)), "the full streamed answer")
    }

    @Test func aGapFetchesAfterTheEndCursor() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { request in
            guard request.direction == .after else { return try Load.page(before: 8) }
            var response = try Load.page(before: 8)
            response.direction = .after
            response.entries = []
            response.hasNewer = false
            return response
        }
        client.onSetSubscription { _ in try Load.subscription() }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }
        #expect(store.timeline.endCursor?.seq == 7)

        let gap = try #require(try Load.stream().first { $0.seq == 10 })
        client.push(.agentStream(gap))

        let fetched = await eventually {
            client.requests(FetchAgentTimelineRequest.self).contains {
                $0.direction == .after && $0.cursor?.seq == 7 && $0.limit == 0
            }
        }
        #expect(fetched)
    }

    @Test func sendShowsPendingRowBeforeTheRequestResolves() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        let gate = Gate()
        let response = try Load.sendMessage()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSendMessage { _ in
            await gate.wait()
            return response
        }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }

        store.draft = "hello there"
        let sending = Task { await store.send("hello there") }

        let pending = await eventually { store.timeline.rows.contains { $0.isPending } }
        #expect(pending)
        #expect(store.draft.isEmpty)

        let recorded = await eventually { !client.requests(SendAgentMessageRequest.self).isEmpty }
        #expect(recorded)
        let request = try #require(client.requests(SendAgentMessageRequest.self).first)
        #expect(request.agentId == agentId)
        #expect(request.text == "hello there")
        #expect(request.messageId?.isEmpty == false)
        #expect(request.activeTurnBehavior == nil)

        let pendingRow = try #require(store.timeline.rows.first { $0.isPending })
        guard case .userMessage(let message) = pendingRow.item else {
            Issue.record("pending row should be a user message")
            return
        }
        #expect(message.text == "hello there")
        #expect(message.clientMessageId == request.messageId)
        #expect(store.turns.last?.userMessage?.id == pendingRow.id)

        await gate.open()
        await sending.value
        #expect(store.actionError == nil)
        #expect(store.timeline.rows.contains { $0.isPending }, "stays until the daemon echoes it")
    }

    @Test func failedSendRemovesPendingRowRestoresDraftAndSetsError() async throws {
        let client = FakeDaemonClient()
        let agents = try Load.agents()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in agents }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        client.onSendMessage { _ in throw FakeDaemonClient.FakeError.noHandler("send") }

        let session = HostSession(client: client)
        await session.start()
        let store = session.conversation(for: agentId)
        _ = await eventually { store.phase == .ready }

        store.draft = "hello there"
        await store.send("hello there")

        #expect(!store.timeline.rows.contains { $0.isPending })
        #expect(store.draft == "hello there")
        #expect(store.actionError != nil)
    }
}
