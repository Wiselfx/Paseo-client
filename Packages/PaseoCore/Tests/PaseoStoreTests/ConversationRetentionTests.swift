import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The retention policy of `HostSession.conversation(for:)`: the most recently used conversations stay
/// open, busy ones are never closed, the rest are closed through the normal close path.
@Suite @MainActor
struct ConversationRetentionTests {
    private func session(limit: Int) -> HostSession {
        let session = HostSession(client: FakeDaemonClient())
        session.retainedConversationLimit = limit
        return session
    }

    @Test func theLeastRecentlyUsedConversationsAreClosedPastTheLimit() {
        let session = session(limit: 3)
        let first = session.conversation(for: "a1")
        for id in ["a2", "a3", "a4"] { _ = session.conversation(for: id) }

        // a1 was the oldest of four, so a new store for it is a different instance (a first open).
        let reopened = session.conversation(for: "a1")
        #expect(reopened !== first)
        // The three newest were kept as they were.
        #expect(session.conversation(for: "a4") === session.conversation(for: "a4"))
    }

    @Test func reSelectingAConversationKeepsItFresh() {
        let session = session(limit: 3)
        let first = session.conversation(for: "a1")
        _ = session.conversation(for: "a2")
        _ = session.conversation(for: "a3")
        // Touch a1 again: a2 is now the oldest.
        _ = session.conversation(for: "a1")
        _ = session.conversation(for: "a4")

        #expect(session.conversation(for: "a1") === first)
    }

    @Test func aConversationWithUnsentTextIsNeverClosed() {
        let session = session(limit: 2)
        let first = session.conversation(for: "a1")
        first.draft = "unsent words"
        for id in ["a2", "a3", "a4", "a5"] { _ = session.conversation(for: id) }

        #expect(session.conversation(for: "a1") === first)
        #expect(first.draft == "unsent words")
    }

    @Test func theFocusedConversationIsNeverClosed() {
        let session = session(limit: 2)
        let first = session.conversation(for: "a1")
        session.attention.setFocusedAgent("a1")
        for id in ["a2", "a3", "a4", "a5"] { _ = session.conversation(for: id) }

        #expect(session.conversation(for: "a1") === first)
    }

    @Test func aPendingSendKeepsTheConversation() {
        let session = session(limit: 2)
        let first = session.conversation(for: "a1")
        first.showPendingSend(text: "hello", clientId: "c1", timestamp: "2026-01-01T00:00:00.000Z")
        for id in ["a2", "a3", "a4"] { _ = session.conversation(for: id) }

        #expect(session.conversation(for: "a1") === first)
    }

    @Test func aClosedConversationUnsubscribesAndAnOpenOneStaysSubscribed() async {
        let client = FakeDaemonClient()
        let session = HostSession(client: client)
        session.retainedConversationLimit = 2
        for id in ["a1", "a2", "a3"] { _ = session.conversation(for: id) }

        let settled = await eventually {
            guard let last = client.requests(SetAgentTimelineSubscriptionRequest.self).last else { return false }
            return Set(last.agentIds) == ["a2", "a3"]
        }
        #expect(settled)
    }
}
