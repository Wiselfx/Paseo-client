import Foundation
import PaseoProtocol
import Testing

/// Wire round-trip coverage for the diagnostics requests (`diagnostics.request`,
/// `provider_diagnostic_request`): the request envelope shape and the response payload decode.
@Suite struct DiagnosticsWireTests {
    private func messageJSON<R: PaseoRequest>(_ request: R) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["type"] as? String == "session")
        return try #require(root["message"] as? [String: Any])
    }

    private func decodePayload<T: Decodable & Sendable>(
        _ type: String, _ json: String, as: T.Type
    ) throws -> T {
        let envelope = """
        {"type":"session","message":{"type":"\(type)","payload":\(json)}}
        """
        return try JSONDecoder().decode(
            SessionPayloadEnvelope<T>.self, from: Data(envelope.utf8)).payload
    }

    @Test func daemonDiagnosticsRequestGetsTheSessionEnvelope() throws {
        let message = try messageJSON(DaemonDiagnosticsRequest())
        #expect(message["type"] as? String == "diagnostics.request")
        #expect(message.keys.contains("requestId"))
    }

    @Test func daemonDiagnosticsResponseDecodes() throws {
        let response = try decodePayload(
            "diagnostics.response",
            #"{"requestId":"r-1","diagnostic":"daemon ok"}"#,
            as: DaemonDiagnosticsRequest.Response.self)
        #expect(response.requestId == "r-1")
        #expect(response.diagnostic == "daemon ok")
    }

    @Test func providerDiagnosticRequestGetsTheSessionEnvelope() throws {
        let request = ProviderDiagnosticRequest(provider: "claude")
        let message = try messageJSON(request)
        #expect(message["type"] as? String == "provider_diagnostic_request")
        #expect(message["provider"] as? String == "claude")
        #expect(message.keys.contains("requestId"))
    }

    @Test func providerDiagnosticResponseDecodes() throws {
        let response = try decodePayload(
            "provider_diagnostic_response",
            #"{"requestId":"r-2","provider":"claude","diagnostic":"claude: ok"}"#,
            as: ProviderDiagnosticRequest.Response.self)
        #expect(response.requestId == "r-2")
        #expect(response.provider == "claude")
        #expect(response.diagnostic == "claude: ok")
    }
}
