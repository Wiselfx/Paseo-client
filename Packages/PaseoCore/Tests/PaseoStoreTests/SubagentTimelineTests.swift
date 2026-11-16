import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The provider-timeline page fetch behind the read-only subagent timeline view.
/// Wire shape per messages.ts `ProviderSubagentTimelineResponseMessageSchema` — projected
/// `rows`, not `entries`. The sandbox agent has no provider subagents, so no live fixture was
/// capturable; the rows ride the shared TimelineItem decode, which is fixture-covered.
@Suite @MainActor
struct SubagentTimelineTests {
    private nonisolated static func timelinePageData(
        rows: String, error: String? = nil
    ) throws -> Data {
        let errorValue = error.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"type":"session","message":{"type":"agent.provider_subagents.timeline.get.response",
          "payload":{"requestId":"subagent-timeline","parentAgentId":"agent-1","subagentId":"sub-1",
          "provider":"opencode","direction":"tail","epoch":"epoch-1",
          "reset":true,"staleCursor":false,"gap":false,
          "window":{"minSeq":1,"maxSeq":2,"nextSeq":3},
          "hasOlder":false,"hasNewer":false,
          "rows":[\(rows)],"error":\(errorValue)}}}
        """
        return Data(json.utf8)
    }

    private nonisolated static func rowJSON(seq: Int, extra: String) -> String {
        """
        {"item":\(extra),"timestamp":"2026-11-09T07:42:00.000Z",
         "seq":\(seq),"seqStart":\(seq),"seqEnd":\(seq)}
        """
    }

    @Test func timelinePageReturnsRows() async throws {
        let userRow = Self.rowJSON(
            seq: 1,
            extra: #"{"type":"user_message","text":"summarize the diff","messageId":"m-1"}"#)
        let assistantRow = Self.rowJSON(
            seq: 2,
            extra: #"{"type":"assistant_message","text":"It touches four files."}"#)
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentTimelineRequest.self) { _ in
            let decoded = try JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderSubagentTimelineRequest.Response>.self,
                from: Self.timelinePageData(rows: "\(userRow),\(assistantRow)"))
            return decoded.payload
        }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1", limit: 5)

        #expect(page?.rows.count == 2)
        #expect(page?.epoch == "epoch-1")
        #expect(page?.window.nextSeq == 3)
        #expect(subagents.error == nil)
        let request = try #require(client.requests(ProviderSubagentTimelineRequest.self).first)
        #expect(request.parentAgentId == "agent-1")
        #expect(request.subagentId == "sub-1")
        #expect(request.direction == .tail)
        #expect(request.limit == 5)
    }

    @Test func timelinePageSurfacesDaemonError() async throws {
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentTimelineRequest.self) { _ in
            let decoded = try JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderSubagentTimelineRequest.Response>.self,
                from: Self.timelinePageData(
                    rows: "", error: "Provider does not support subagent timelines"))
            return decoded.payload
        }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1")

        // A refusal surfaces as nil page plus the daemon's message on the store.
        #expect(page?.rows == nil)
        #expect(subagents.error == "Provider does not support subagent timelines")
    }

    @Test func timelinePageSurfacesTransportFailure() async {
        struct Boom: Error {}
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentTimelineRequest.self) { _ in throw Boom() }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1")

        #expect(page?.rows.isEmpty != true)
        #expect(subagents.error != nil)
    }
}
