import Foundation
import PaseoProtocol
import Testing

/// B8: `agent.detach.request` / `agent.detach.response` (upstream `AgentDetachRequestMessageSchema`
/// / `AgentDetachResponseMessageSchema`, messages.ts:2151-2161).
@Suite
struct DetachWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["message"] as? [String: Any])
    }

    @Test func requestUsesTheNamespacedType() throws {
        let message = try messageJSON(AgentDetachRequest(agentId: "child-agent"))
        #expect(message["type"] as? String == "agent.detach.request")
        #expect(message["agentId"] as? String == "child-agent")
        #expect(AgentDetachRequest.responseType == "agent.detach.response")
    }

    @Test func requestIdTravelsOnTheWire() throws {
        var request = AgentDetachRequest(agentId: "child-agent")
        request.requestId = "req-9"
        let message = try messageJSON(request)
        #expect(message["requestId"] as? String == "req-9")
    }

    @Test func responseDecodesTheSharedActionPayload() throws {
        let json = """
            {"requestId":"req-9","agentId":"child-agent","accepted":true,"error":null}
            """
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentDetachRequest.Response>.self,
            from: Data(
                #"{"type":"session","message":{"type":"agent.detach.response","payload":\#(json)}}"#
                    .utf8)
        ).payload
        #expect(response.requestId == "req-9")
        #expect(response.agentId == "child-agent")
        #expect(response.accepted)
        #expect(response.error == nil)
    }

    @Test func rejectionCarriesTheDaemonMessage() throws {
        let json = """
            {"requestId":"req-9","agentId":"child-agent","accepted":false,"error":"No parent"}
            """
        let response = try JSONDecoder().decode(
            AgentActionResponse.self, from: Data(json.utf8))
        #expect(!response.accepted)
        #expect(response.error == "No parent")
    }
}
