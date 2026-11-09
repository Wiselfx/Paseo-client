import Foundation
import PaseoProtocol
import Testing

/// M15: the hello advertises the `voice` client capability behind `VoiceMode.isEnabled`.
@Suite struct VoiceCapabilityHelloTests {
    @Test func voiceCapabilityIsImplementedAndOnTheWire() throws {
        #expect(VoiceMode.isEnabled)
        #expect(VoiceMode.capability == "voice")
        #expect(ClientCapabilities.implemented["voice"] == true)

        let hello = Hello(clientId: "client-1", appVersion: "0.1.0", credential: .password("pw"))
        let data = try JSONEncoder().encode(hello)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(value["capabilities"]?["voice"] == .bool(true))
        #expect(value["capabilities"]?["owned_subscriptions"] == .bool(true))
    }
}
