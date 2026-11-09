import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M7f: the provider-timeline page fetch behind the read-only subagent timeline view.
/// The sandbox agent has no provider subagents (one dies with its provider session), so no
/// live fixture exists; the page is built inline from the documented wire shape. The entries
/// inside are fixture-covered elsewhere (fetch_agent_timeline_response).
@Suite @MainActor
struct SubagentTimelineTests {
    private nonisolated static func timelinePageData(
        entries: String, error: String? = nil
    ) throws -> Data {
        let errorValue = error.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"type":"session","message":{"type":"agent.provider_subagents.timeline.get.response",
          "payload":{"requestId":"subagent-timeline","parentAgentId":"agent-1","subagentId":"sub-1",
          "provider":"opencode","epoch":"epoch-1","reset":true,"gap":false,
          "entries":[\(entries)],"hasOlder":false,"hasNewer":false,"error":\(errorValue)}}}
        """
        return Data(json.utf8)
    }

    private nonisolated static func entryJSON(seq: Int, extra: String) -> String {
        """
        {"provider":"opencode","item":\(extra),"timestamp":"2026-11-09T07:42:00.000Z",
         "seqStart":\(seq),"seqEnd":\(seq)}
        """
    }

    @Test func timelinePageReturnsEntries() async throws {
        let userEntry = Self.entryJSON(
            seq: 1,
            extra: #"{"type":"user_message","text":"summarize the diff","messageId":"m-1"}"#)
        let assistantEntry = Self.entryJSON(
            seq: 2,
            extra: #"{"type":"assistant_message","text":"It touches four files."}"#)
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentTimelineRequest.self) { _ in
            let decoded = try JSONDecoder().decode(
                SessionPayloadEnvelope<ProviderSubagentTimelineRequest.Response>.self,
                from: Self.timelinePageData(entries: "\(userEntry),\(assistantEntry)"))
            return decoded.payload
        }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1", limit: 5)

        #expect(page?.entries.count == 2)
        #expect(page?.epoch == "epoch-1")
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
                    entries: "", error: "Provider does not support subagent timelines"))
            return decoded.payload
        }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1")

        #expect(page?.entries == nil)
        #expect(subagents.error == "Provider does not support subagent timelines")
    }

    @Test func timelinePageSurfacesTransportFailure() async {
        struct Boom: Error {}
        let client = FakeDaemonClient()
        client.onSend(ProviderSubagentTimelineRequest.self) { _ in throw Boom() }

        let subagents = ConversationSubagents(agentId: "agent-1", client: client)
        let page = await subagents.timelinePage(for: "sub-1")

        #expect(page?.entries == nil)
        #expect(subagents.error != nil)
    }
}
