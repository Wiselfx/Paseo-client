import Foundation
import PaseoProtocol
import Testing

/// V1: the compaction item gained optional `trigger` and `preTokens` (`messages.ts:772-776`).
/// Old daemons send only `status`, and the item must keep decoding for them.
@Suite struct CompactionItemWireTests {
    private nonisolated static func item(_ json: String) throws -> TimelineItem {
        try JSONDecoder().decode(TimelineItem.self, from: Data(json.utf8))
    }

    @Test func legacyPayloadDecodesWithOnlyStatus() throws {
        let item = try Self.item(#"{"type":"compaction","status":"loading"}"#)

        guard case .compaction(let status, let trigger, let preTokens) = item else {
            Issue.record("expected a compaction item, got \(item)")
            return
        }
        #expect(status == "loading")
        #expect(trigger == nil)
        #expect(preTokens == nil)
    }

    @Test func fullPayloadDecodesEveryField() throws {
        let item = try Self.item(
            #"{"type":"compaction","status":"completed","trigger":"auto","preTokens":41234}"#)

        guard case .compaction(let status, let trigger, let preTokens) = item else {
            Issue.record("expected a compaction item, got \(item)")
            return
        }
        #expect(status == "completed")
        #expect(trigger == "auto")
        #expect(preTokens == 41234)
    }

    @Test func manualTriggerSurvives() throws {
        let item = try Self.item(
            #"{"type":"compaction","status":"completed","trigger":"manual"}"#)

        guard case .compaction(_, let trigger, let preTokens) = item else {
            Issue.record("expected a compaction item, got \(item)")
            return
        }
        #expect(trigger == "manual")
        #expect(preTokens == nil)
    }

    @Test func unknownTriggerAndBadTokenCountDoNotBreakTheItem() throws {
        // A newer daemon may add a trigger value, and `preTokens` is a number on the wire; neither
        // may take the whole timeline page down with it.
        let item = try Self.item(
            #"{"type":"compaction","status":"completed","trigger":"overflow","preTokens":"soon"}"#)

        guard case .compaction(let status, let trigger, let preTokens) = item else {
            Issue.record("expected a compaction item, got \(item)")
            return
        }
        #expect(status == "completed")
        #expect(trigger == "overflow")
        #expect(preTokens == nil)
    }

    @Test func compactionStillDecodesInsideATimelineResponse() throws {
        // The item union is also decoded through the timeline response, not in isolation: guard
        // the envelope path too.
        let json = """
        {"message":{"type":"fetch_agent_timeline_response","payload":{
          "requestId":"req_1","agentId":"agent_1","direction":"tail","epoch":"epoch_1",
          "reset":false,"staleCursor":false,"gap":false,
          "window":{"minSeq":1,"maxSeq":2,"nextSeq":3},
          "hasOlder":false,"hasNewer":false,
          "entries":[
            {"provider":"claude","item":{"type":"user_message","text":"hi"},
             "timestamp":"2026-01-01T00:00:00.000Z","seqStart":1,"seqEnd":1},
            {"provider":"claude","item":{"type":"compaction","status":"completed",
             "trigger":"auto","preTokens":99000},
             "timestamp":"2026-01-01T00:00:01.000Z","seqStart":2,"seqEnd":2}
          ]}}}
        """
        let envelope = try JSONDecoder().decode(
            SessionPayloadEnvelope<FetchAgentTimelineRequest.Response>.self, from: Data(json.utf8))

        #expect(envelope.payload.entries.count == 2)
        guard case .compaction(let status, let trigger, let preTokens) =
            envelope.payload.entries[1].item
        else {
            Issue.record("expected the second entry to be a compaction item")
            return
        }
        #expect(status == "completed")
        #expect(trigger == "auto")
        #expect(preTokens == 99000)
    }
}
