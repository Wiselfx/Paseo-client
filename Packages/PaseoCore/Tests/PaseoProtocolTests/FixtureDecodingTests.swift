import Foundation
import Testing
@testable import PaseoProtocol
import PaseoFixtures

@Suite struct FixtureDecodingTests {
    let decoder = JSONDecoder()

    @Test func serverInfo() throws {
        let data = try Fixture.data("server_info")
        let header = try decoder.decode(InboundHeader.self, from: data)
        #expect(header.type == "session")
        #expect(header.messageType == "status")
        #expect(header.status == "server_info")
        let info = try decoder.decode(SessionPayloadEnvelope<ServerInfo>.self, from: data).payload
        #expect(info.serverId == "srv_FIXTURE")
        #expect(info.protocolVersion == 1)
    }

    @Test func agents() throws {
        let data = try Fixture.data("fetch_agents_response")
        #expect(try decoder.decode(InboundHeader.self, from: data).requestId == "agents")
        let response = try decoder.decode(SessionPayloadEnvelope<FetchAgentsRequest.Response>.self, from: data).payload
        let agent = try #require(response.entries.first?.agent)
        #expect(agent.provider == "opencode")
        #expect(agent.status == .idle)
    }

    @Test func timelinePage() throws {
        let data = try Fixture.data("fetch_agent_timeline_response")
        let page = try decoder.decode(SessionPayloadEnvelope<FetchAgentTimelineRequest.Response>.self, from: data).payload
        #expect(!page.entries.isEmpty)
        #expect(page.entries.allSatisfy { $0.seqStart <= $0.seqEnd })
        let kinds = Set(page.entries.map { entry -> String in
            switch entry.item {
            case .toolCall: "tool"
            case .reasoning: "reasoning"
            case .assistantMessage: "assistant"
            case .userMessage: "user"
            default: "other"
            }
        })
        #expect(kinds.isSuperset(of: ["tool", "reasoning", "assistant", "user"]))
        // Projected rows are settled: no tool call is left in `running`.
        for case .toolCall(let call) in page.entries.map(\.item) { #expect(call.status.isTerminal) }
    }

    @Test func liveStreamDecodesEveryFrame() throws {
        var sawStart = false, sawEnd = false, sawShell = false, sawSearch = false
        for data in try Fixture.streamFrames() {
            #expect(try decoder.decode(InboundHeader.self, from: data).messageType == "agent_stream")
            let payload = try decoder.decode(SessionPayloadEnvelope<AgentStreamPayload>.self, from: data).payload
            switch payload.event {
            case .turnStarted: sawStart = true
            case .turnCompleted: sawEnd = true
            case .timeline(let item, _):
                #expect(payload.seq != nil)
                if case .toolCall(let call) = item {
                    if case .shell = call.detail { sawShell = true }
                    if case .search = call.detail { sawSearch = true }
                }
            default: break
            }
        }
        #expect(sawStart && sawEnd && sawShell && sawSearch)
    }

    @Test func unknownItemTypesDoNotThrow() throws {
        let json = #"{"type":"hologram","beam":3}"#
        let item = try decoder.decode(TimelineItem.self, from: Data(json.utf8))
        guard case .unknown(let type, _) = item else { Issue.record("expected unknown"); return }
        #expect(type == "hologram")
        let detail = try decoder.decode(ToolCallDetail.self, from: Data(#"{"type":"teleport"}"#.utf8))
        guard case .unknown = detail else { Issue.record("expected unknown detail"); return }
    }

    @Test func requestEnvelopeIsFlatWithType() throws {
        var request = SendAgentMessageRequest(agentId: "a1", text: "hi", messageId: "m1")
        request.requestId = "r1"
        let object = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(SessionRequestEnvelope(request)))
        #expect(object["type"] == .string("session"))
        #expect(object["message"]?["type"] == .string("send_agent_message_request"))
        #expect(object["message"]?["requestId"] == .string("r1"))
        #expect(object["message"]?["text"] == .string("hi"))
    }
}
