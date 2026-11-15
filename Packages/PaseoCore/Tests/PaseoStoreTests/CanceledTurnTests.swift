import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// A stopped turn (`turn_canceled`) is recorded by its daemon turn id, so the transcript can show
/// no completion text for it (N5 A).
@Suite @MainActor
struct CanceledTurnTests {
    private func makeStore() -> ConversationStore {
        ConversationStore(agentId: "agent-1", client: FakeDaemonClient())
    }

    @Test func turnCanceledRecordsTheTurnId() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_canceled",
            "turnId": "turn-1",
            "reason": "interrupted",
        ])
        await store.handleStream(payload)

        #expect(store.canceledTurnIds == ["turn-1"])
    }

    @Test func turnCanceledWithoutATurnIdRecordsNothing() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_canceled",
            "reason": "interrupted",
        ])
        await store.handleStream(payload)

        #expect(store.canceledTurnIds.isEmpty)
    }

    @Test func turnCompletedIsNotRecordedAsCanceled() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_completed",
            "turnId": "turn-2",
        ])
        await store.handleStream(payload)

        #expect(store.canceledTurnIds.isEmpty)
    }

    @Test func turnFailedIsNotRecordedAsCanceled() async throws {
        let store = makeStore()
        let payload = try Self.streamPayload(agentId: "agent-1", event: [
            "type": "turn_failed",
            "turnId": "turn-3",
            "error": "boom",
        ])
        await store.handleStream(payload)

        #expect(store.canceledTurnIds.isEmpty)
    }

    @Test func aCanceledIdIsKeptOncePerTurn() async throws {
        let store = makeStore()
        for _ in 0..<2 {
            let payload = try Self.streamPayload(agentId: "agent-1", event: [
                "type": "turn_canceled",
                "turnId": "turn-1",
                "reason": "interrupted",
            ])
            await store.handleStream(payload)
        }

        #expect(store.canceledTurnIds.count == 1)
    }

    private static func streamPayload(
        agentId: String, event: [String: Any]
    ) throws -> AgentStreamPayload {
        let object: [String: Any] = [
            "agentId": agentId,
            "event": event,
            "timestamp": "2026-11-15T00:00:00.000Z",
        ]
        return try JSONDecoder().decode(
            AgentStreamPayload.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
