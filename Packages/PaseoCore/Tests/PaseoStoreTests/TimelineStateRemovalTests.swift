import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite struct PendingUserMessageRemovalTests {
    @Test func removesOnlyTheMatchingPendingMessage() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        state.addPendingUserMessage(text: "one", clientMessageId: "c1", timestamp: "2026-11-08T21:00:00.000Z")
        state.addPendingUserMessage(text: "two", clientMessageId: "c2", timestamp: "2026-11-08T21:00:01.000Z")

        state.removePendingUserMessage(clientMessageId: "c1")

        #expect(state.rows.filter(\.isPending).map(\.id) == ["local:c2"])
    }

    @Test func confirmedMessageIsNotRemoved() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        state.addPendingUserMessage(
            text: "Think briefly first…", clientMessageId: "fixture-msg-1",
            timestamp: "2026-11-08T21:00:00.000Z")
        let echo = try #require(try Load.stream().first { $0.seq == 8 })
        #expect(state.applyStream(echo) == .applied)
        #expect(!state.rows.contains { $0.isPending })

        state.removePendingUserMessage(clientMessageId: "fixture-msg-1")

        #expect(state.rows.contains { $0.id == "local:fixture-msg-1" })
    }
}
