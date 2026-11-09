import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

/// T17: the hello advertises `owned_subscriptions` (and its `workspace_setup_observation`
/// companion) behind one switch, and the daemon feature gates the modern paths.
@Suite struct OwnedSubscriptionsCapabilityTests {
    @Test func theSwitchIsOnAndAdvertisesExactlyTheImplementedCapabilities() {
        #expect(OwnedSubscriptions.isEnabled)
        #expect(OwnedSubscriptions.capability == "owned_subscriptions")
        #expect(OwnedSubscriptions.setupObservationCapability == "workspace_setup_observation")
        #expect(
            ClientCapabilities.implemented
                == [
                    "hello_rejection": true,
                    "terminal_chunked_replay": true,
                    "providerSubagents": true,
                    "owned_subscriptions": true,
                    "workspace_setup_observation": true,
                ])
    }

    @Test func helloOnTheWireCarriesTheCapabilities() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        let hello = try JSONDecoder().decode(
            JSONValue.self, from: Data(try #require(transport.outbound.first).utf8))

        #expect(hello["capabilities"]?["owned_subscriptions"] == .bool(true))
        #expect(hello["capabilities"]?["workspace_setup_observation"] == .bool(true))

        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)
    }

    @Test func serverInfoFeatureGatesTheModernPaths() throws {
        let info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self, from: Fixture.data("server_info")
        ).payload
        #expect(info.hasFeature("ownedSubscriptions"))
        #expect(info.supportsOwnedSubscriptions)

        var legacy = info
        legacy.features?["ownedSubscriptions"] = .bool(false)
        #expect(!legacy.supportsOwnedSubscriptions)

        var missing = info
        missing.features = nil
        #expect(!missing.supportsOwnedSubscriptions)
    }
}
