import Foundation
import PaseoProtocol
import Testing

/// U5 wire coverage for the chat outline: `agent.timeline.list_prompts` (the prompt index) and the
/// `mergeWindow` flag the prompt jump adds to `fetch_agent_timeline_request`.
///
/// Source: packages/protocol/src/messages.ts `AgentTimelineListPromptsRequestMessageSchema`
/// (:2012-2016), `AgentTimelineListPromptsResponseMessageSchema` (:4998-5016) and
/// `FetchAgentTimelineRequestMessageSchema.mergeWindow` (:2000-2001).
@Suite struct TimelinePromptIndexWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "session")
        return try #require(root["message"] as? [String: Any])
    }

    @Test func promptIndexRequestEncodesTypeAndAgent() throws {
        let message = try messageJSON(AgentTimelinePromptIndexRequest(agentId: "agent-1"))
        #expect(message["type"] as? String == "agent.timeline.list_prompts.request")
        #expect(message["agentId"] as? String == "agent-1")
        #expect(message["requestId"] != nil)
    }

    @Test func promptIndexResponseDecodesTheDaemonPayload() throws {
        let json = """
            {"type":"session","message":{"type":"agent.timeline.list_prompts.response","payload":{
              "requestId":"r1","agentId":"agent-1","epoch":"epoch-7",
              "prompts":[
                {"seq":3,"timestamp":"2026-11-08T21:00:01.000Z","preview":"First prompt"},
                {"seq":41,"timestamp":"2026-11-08T21:01:00.000Z","preview":"Second prompt"}
              ],
              "error":null}}}
            """
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentTimelinePromptIndexRequest.Response>.self,
            from: Data(json.utf8)
        ).payload
        #expect(response.requestId == "r1")
        #expect(response.agentId == "agent-1")
        #expect(response.epoch == "epoch-7")
        #expect(response.prompts.map(\.seq) == [3, 41])
        #expect(response.prompts.map(\.preview) == ["First prompt", "Second prompt"])
        #expect(response.prompts.map(\.id) == [3, 41])
        #expect(response.error == nil)
    }

    @Test func promptIndexResponseToleratesAnOlderDaemonError() throws {
        let json = """
            {"type":"session","message":{"type":"agent.timeline.list_prompts.response","payload":{
              "requestId":"r1","agentId":"agent-1","epoch":"","prompts":[],
              "error":"Unknown message type"}}}
            """
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentTimelinePromptIndexRequest.Response>.self,
            from: Data(json.utf8)
        ).payload
        #expect(response.epoch.isEmpty)
        #expect(response.prompts.isEmpty)
        #expect(response.error == "Unknown message type")
    }

    @Test func promptIndexResponseToleratesMissingFields() throws {
        let json = """
            {"type":"session","message":{"type":"agent.timeline.list_prompts.response",
             "payload":{"requestId":"r1"}}}
            """
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentTimelinePromptIndexRequest.Response>.self,
            from: Data(json.utf8)
        ).payload
        #expect(response.prompts.isEmpty)
        #expect(response.epoch.isEmpty)
        #expect(response.error == nil)
    }

    @Test func promptJumpWindowEncodesMergeWindow() throws {
        var request = FetchAgentTimelineRequest(
            agentId: "agent-1", direction: .before,
            cursor: TimelineCursor(epoch: "epoch-7", seq: 61), limit: 40)
        request.mergeWindow = true
        let message = try messageJSON(request)
        #expect(message["type"] as? String == "fetch_agent_timeline_request")
        #expect(message["direction"] as? String == "before")
        #expect(message["limit"] as? Int == 40)
        #expect(message["wholeTurns"] as? Bool == true)
        #expect(message["mergeWindow"] as? Bool == true)
        let cursor = try #require(message["cursor"] as? [String: Any])
        #expect(cursor["epoch"] as? String == "epoch-7")
        #expect(cursor["seq"] as? Int == 61)
    }

    @Test func ordinaryTimelineFetchOmitsMergeWindow() throws {
        let message = try messageJSON(
            FetchAgentTimelineRequest(agentId: "agent-1", direction: .tail, limit: 40))
        #expect(message["mergeWindow"] == nil)
    }
}
