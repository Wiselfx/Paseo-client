import Foundation
import Testing
@testable import PaseoProtocol
@testable import PaseoStore

/// Wire + presentation tests for `agentMessage` (upstream `protocol/src/agent-types.ts:342`,
/// `protocol/src/agent-message.ts:4-12`, `app/src/agent-stream/presentation.ts:88-103`).
@Suite struct AgentMessageTests {
    // MARK: - Wire decoding

    @Test func decodesAgentMessageOnToolCall() throws {
        let call = try decodeToolCall("""
        {"type":"tool_call","callId":"paseo-agent-message:1","name":"agent_message","status":"completed","error":null,
         "agentMessage":{"event":"message","sender":{"id":"worker","title":"PR helper"},"text":"please look"},
         "detail":{"type":"plain_text","text":"please look","icon":"bot"}}
        """)
        let message = try #require(call.agentMessage)
        #expect(message.event == .message)
        #expect(message.sender.id == "worker")
        #expect(message.sender.title == "PR helper")
        #expect(message.sender.serverId == nil)
        #expect(message.text == "please look")
    }

    @Test func missingAgentMessageDecodesToNil() throws {
        let call = try decodeToolCall("""
        {"type":"tool_call","callId":"c1","name":"Bash","status":"completed","error":null,
         "detail":{"type":"shell","command":"ls"}}
        """)
        #expect(call.agentMessage == nil)
    }

    @Test func unknownEventDecodesAndIsNotMessage() throws {
        let call = try decodeToolCall("""
        {"type":"tool_call","callId":"c1","name":"agent_message","status":"completed","error":null,
         "agentMessage":{"event":"something-new","sender":{"id":"w"},"text":"hi"},
         "detail":{"type":"plain_text","text":"hi"}}
        """)
        let message = try #require(call.agentMessage)
        #expect(message.event == .unknown("something-new"))
        #expect(message.event != .message)
        #expect(message.sender.id == "w")
        #expect(message.text == "hi")
    }

    @Test func knownNonMessageEventsDecode() throws {
        for (raw, expected) in [("finished", TimelineItem.AgentMessage.Event.finished),
                                ("errored", .errored),
                                ("permission-required", .permissionRequired),
                                ("closed", .closed)] {
            let call = try decodeToolCall("""
            {"type":"tool_call","callId":"c1","name":"agent_message","status":"completed","error":null,
             "agentMessage":{"event":"\(raw)","sender":{"id":"w"},"text":"hi"},
             "detail":{"type":"plain_text","text":"hi"}}
            """)
            #expect(try #require(call.agentMessage).event == expected)
        }
    }

    @Test func decodesSenderServerIDAndMissingTitle() throws {
        let call = try decodeToolCall("""
        {"type":"tool_call","callId":"c1","name":"agent_message","status":"completed","error":null,
         "agentMessage":{"event":"message","sender":{"id":"w","serverId":"srv"},"text":"hi"},
         "detail":{"type":"plain_text","text":"hi"}}
        """)
        let sender = try #require(call.agentMessage).sender
        #expect(sender.serverId == "srv")
        #expect(sender.title == nil)
    }

    @Test func userMessageWithoutSenderDecodesToNil() throws {
        let item = try decodeItem("""
        {"type":"user_message","text":"hello","messageId":"m1"}
        """)
        guard case .userMessage(let message) = item else { Issue.record("expected userMessage"); return }
        #expect(message.sender == nil)
        #expect(message.text == "hello")
    }

    // MARK: - Timeline mapping

    @Test func messageToolCallProjectsToUserMessage() {
        let call = ToolCall(callId: "paseo-agent-message:1", name: "agent_message", status: .completed,
                            detail: .plainText(label: nil, text: "please look", icon: nil), error: nil,
                            agentMessage: .init(event: .message, sender: .init(id: "worker", title: "PR helper"), text: "please look"))
        let projected = TimelineState.presentedItem(.toolCall(call))
        guard case .userMessage(let message) = projected else { Issue.record("expected userMessage"); return }
        #expect(message.text == "please look")
        #expect(message.sender?.id == "worker")
        #expect(message.sender?.title == "PR helper")
        #expect(TurnSummary.sentByLabel(name: TurnSummary.senderName(agentTitle: nil, senderTitle: message.sender?.title, senderID: message.sender?.id ?? "")) == "Sent by PR helper")
    }

    @Test func nonMessageAndMissingStayToolCalls() {
        let finished = ToolCall(callId: "c1", name: "agent_message", status: .completed,
                                detail: .plainText(label: nil, text: "done", icon: nil), error: nil,
                                agentMessage: .init(event: .finished, sender: .init(id: "w"), text: "done"))
        guard case .toolCall = TimelineState.presentedItem(.toolCall(finished)) else {
            Issue.record("finished must stay a tool call"); return
        }
        let plain = ToolCall(callId: "c2", name: "Bash", status: .completed,
                             detail: .shell(command: "ls", cwd: nil, output: nil, exitCode: nil), error: nil)
        guard case .toolCall = TimelineState.presentedItem(.toolCall(plain)) else {
            Issue.record("plain call must stay a tool call"); return
        }
    }

    @Test func pageRowPreservesToolIDForProjectedItem() throws {
        var state = TimelineState()
        state.applyPage(try makePage(entryJSONs: ["""
        {"provider":"opencode","item":{"type":"tool_call","callId":"paseo-agent-message:1","name":"agent_message","status":"completed","error":null,"agentMessage":{"event":"message","sender":{"id":"worker"},"text":"hi"},"detail":{"type":"plain_text","text":"hi"}},"turnId":"t1","timestamp":"2026-11-08T21:02:50.377Z","seqStart":2,"seqEnd":3}
        """]))
        let rows = state.rows
        #expect(rows.count == 1)
        #expect(rows[0].id == "tool:paseo-agent-message:1")
        guard case .userMessage(let message) = rows[0].item else { Issue.record("expected userMessage"); return }
        #expect(message.text == "hi")
        #expect(message.sender?.id == "worker")
    }

    @Test func streamRowPreservesToolIDForProjectedItem() throws {
        var state = TimelineState()
        state.applyPage(try makePage(entryJSONs: [], epoch: "e", nextSeq: 5))
        let event = try decodeStreamEvent(seq: 5)
        #expect(state.applyStream(event) == .applied)
        #expect(state.rows.count == 1)
        #expect(state.rows[0].id == "tool:paseo-agent-message:1")
        guard case .userMessage = state.rows[0].item else { Issue.record("expected userMessage"); return }
    }

    // MARK: - Helpers

    private func decodeToolCall(_ json: String) throws -> ToolCall {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(ToolCall.self, from: data)
    }

    private func decodeItem(_ json: String) throws -> TimelineItem {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(TimelineItem.self, from: data)
    }

    private func decodeStreamEvent(seq: Int) throws -> AgentStreamPayload {
        // Build via JSON so the wire round-trip exercises the same decoder as production.
        let json = """
        {"agentId":"a","seq":\(seq),"epoch":"e","timestamp":"2026-11-08T21:02:50.000Z","event":{"type":"timeline","turnId":"t1","item":{"type":"tool_call","callId":"paseo-agent-message:1","name":"agent_message","status":"completed","error":null,"agentMessage":{"event":"message","sender":{"id":"worker"},"text":"hi"},"detail":{"type":"plain_text","text":"hi"}}}}
        """
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(AgentStreamPayload.self, from: data)
    }

    private func makePage(entryJSONs: [String], epoch: String = "e", nextSeq: Int = 5) throws -> FetchAgentTimelineRequest.Response {
        let json = """
        {"requestId":"r","agentId":"a","direction":"tail","epoch":"\(epoch)","reset":false,"staleCursor":false,"gap":false,"window":{"minSeq":0,"maxSeq":\(nextSeq - 1),"nextSeq":\(nextSeq)},"hasOlder":false,"hasNewer":false,"entries":[\(entryJSONs.joined(separator: ","))]}
        """
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(FetchAgentTimelineRequest.Response.self, from: data)
    }
}
