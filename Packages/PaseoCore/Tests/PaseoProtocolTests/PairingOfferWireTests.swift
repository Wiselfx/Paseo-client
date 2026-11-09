import Foundation
import PaseoProtocol
import Testing

/// Wire coverage for the pairing offer (`daemon.get_pairing_offer.*`): request envelope
/// shape and response decode, including the relay-disabled shape (fake ids only).
@Suite struct PairingOfferWireTests {
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

    @Test func requestGetsTheSessionEnvelope() throws {
        let message = try messageJSON(DaemonGetPairingOfferRequest())
        #expect(message["type"] as? String == "daemon.get_pairing_offer.request")
        #expect(message.keys.contains("requestId"))
    }

    @Test func enabledResponseDecodes() throws {
        let response = try decodePayload(
            "daemon.get_pairing_offer.response",
            #"{"requestId":"r-1","url":"https://example.invalid/#offer=srv_FIXTURE","qr":null,"relayEnabled":true}"#,
            as: DaemonGetPairingOfferRequest.Response.self)
        #expect(response.url == "https://example.invalid/#offer=srv_FIXTURE")
        #expect(response.qr == nil)
        #expect(response.relayEnabled)
    }

    @Test func relayDisabledShapeDecodesWithNilURL() throws {
        let response = try decodePayload(
            "daemon.get_pairing_offer.response",
            #"{"requestId":"r-2","url":null,"qr":null,"relayEnabled":false}"#,
            as: DaemonGetPairingOfferRequest.Response.self)
        #expect(response.url == nil)
        #expect(!response.relayEnabled)
    }
}
