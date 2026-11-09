import Foundation
import PaseoProtocol
import Testing

/// Regression for the M2.5a "model switching does nothing / composer timeout" bugs.
///
/// The daemon validates every request with a zod schema that requires `requestId`. A hand-written
/// encoder that only lists the payload keys drops the correlation id, the daemon refuses the
/// frame, nobody answers and the caller waits out its timeout. The switch never happens.
@Suite
struct AgentConfigRequestEncodingTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        var request = request
        request.requestId = "req-42"
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["message"] as? [String: Any])
    }

    @Test func setModelRequestCarriesItsCorrelationId() throws {
        let message = try messageJSON(
            SetAgentModelRequest(agentId: "agent-1", modelId: "opencode-go/glm-5.3"))

        #expect(message["type"] as? String == "set_agent_model_request")
        #expect(message["requestId"] as? String == "req-42")
        #expect(message["agentId"] as? String == "agent-1")
        #expect(message["modelId"] as? String == "opencode-go/glm-5.3")
    }

    @Test func clearingTheModelStillCarriesItsCorrelationId() throws {
        let message = try messageJSON(SetAgentModelRequest(agentId: "agent-1", modelId: nil))

        #expect(message["requestId"] as? String == "req-42")
        #expect(message["modelId"] is NSNull, "the schema is nullable, so the key must be present")
    }

    @Test func setThinkingRequestCarriesItsCorrelationId() throws {
        let message = try messageJSON(
            SetAgentThinkingRequest(agentId: "agent-1", thinkingOptionId: "high"))

        #expect(message["type"] as? String == "set_agent_thinking_request")
        #expect(message["requestId"] as? String == "req-42")
        #expect(message["agentId"] as? String == "agent-1")
        #expect(message["thinkingOptionId"] as? String == "high")
    }

    @Test func clearingTheThinkingLevelStillCarriesItsCorrelationId() throws {
        let message = try messageJSON(
            SetAgentThinkingRequest(agentId: "agent-1", thinkingOptionId: nil))

        #expect(message["requestId"] as? String == "req-42")
        #expect(message["thinkingOptionId"] is NSNull)
    }
}
