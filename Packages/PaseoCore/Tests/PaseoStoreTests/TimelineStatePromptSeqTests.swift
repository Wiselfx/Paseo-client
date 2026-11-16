import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// P5-A: `TimelineState.latestPromptSeq` is maintained incrementally, so `ConversationStore`
/// need not scan every row on every streamed token.
@Suite struct TimelineStatePromptSeqTests {
    @Test func aStreamedPromptMovesTheNewestPrompt() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        // The page before the streamed turn ends with a projected agent message, which is a
        // user message for outline purposes.
        #expect(state.latestPromptSeq == 2)

        let payloads = try Load.stream().filter { $0.seq != nil }
        guard let first = payloads.first, first.seq == 8 else {
            Issue.record("fixture should start at seq 8")
            return
        }
        _ = state.applyStream(first)
        #expect(state.latestPromptSeq == 8)

        // The rest of the turn is reasoning, tool calls and assistant text.
        for payload in payloads.dropFirst() {
            _ = state.applyStream(payload)
            #expect(state.latestPromptSeq == 8)
        }
    }

    @Test func pendingSendsAreNotPromptsUntilConfirmed() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        #expect(state.latestPromptSeq == 2)

        state.addPendingUserMessage(
            text: "hello", clientMessageId: "fixture-msg-1", timestamp: "2026-11-08T21:00:00.000Z")
        #expect(state.latestPromptSeq == 2, "a pending send is not in the daemon's index")

        let echo = try #require(try Load.stream().first { $0.seq == 8 })
        _ = state.applyStream(echo)
        #expect(state.latestPromptSeq == 8)
    }

    @Test func aPageMergeRecomputesTheNewestPrompt() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        #expect(state.latestPromptSeq == 2)

        state.applyPage(try Load.page())
        #expect(state.latestPromptSeq == 8)
    }

    @Test func removingAPendingSendLeavesTheNewestPromptAlone() throws {
        var state = TimelineState()
        state.applyPage(try Load.page(before: 8))
        let echo = try #require(try Load.stream().first { $0.seq == 8 })
        _ = state.applyStream(echo)
        #expect(state.latestPromptSeq == 8)

        state.addPendingUserMessage(
            text: "never mind", clientMessageId: "c2", timestamp: "2026-11-08T21:00:01.000Z")
        state.removePendingUserMessage(clientMessageId: "c2")
        #expect(state.latestPromptSeq == 8)
    }
}
