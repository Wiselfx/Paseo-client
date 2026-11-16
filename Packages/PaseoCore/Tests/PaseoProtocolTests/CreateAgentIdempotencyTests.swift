import Foundation
import PaseoProtocol
import Testing

/// L3 Part B: `create_agent_request` carries `idempotencyKey` and `clientMessageId` under upstream's
/// exact wire keys, and omits them when unset (packages/protocol/src/messages.ts:1865, :1874).
@Suite struct CreateAgentIdempotencyTests {
    private func body(_ request: CreateAgentRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    }

    private func request() -> CreateAgentRequest {
        CreateAgentRequest(config: AgentSessionConfig(provider: "pi", cwd: "/work/repo"))
    }

    @Test func keysEncodeUnderTheUpstreamWireNames() throws {
        var request = request()
        request.idempotencyKey = "9f1c2a3e-0000-4000-8000-000000000001"
        request.clientMessageId = "msg-7"

        let value = try body(request)
        #expect(value["idempotencyKey"] == .string("9f1c2a3e-0000-4000-8000-000000000001"))
        #expect(value["clientMessageId"] == .string("msg-7"))
        #expect(value["config"]?["provider"] == .string("pi"))
    }

    @Test func keysAreOmittedWhenNil() throws {
        let value = try body(request())
        #expect(value["idempotencyKey"] == nil)
        #expect(value["clientMessageId"] == nil)
        guard case .object(let object) = value else {
            Issue.record("create_agent_request body is not a JSON object")
            return
        }
        #expect(!object.keys.contains("idempotencyKey"))
        #expect(!object.keys.contains("clientMessageId"))
    }
}
