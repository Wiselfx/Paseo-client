import Foundation
import PaseoKit
import PaseoProtocol
import Testing

/// R17: the security floor, its persistence, and the secret path.
///
/// Nothing here may store a secret outside `RelaySecretStore`, and no pin may ever be weakened.
@Suite struct RelayPinningTests {
    static let keyB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    static let otherKeyB64 = "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8="
    static let serverID = "srv_AAAAAAAAAAAA"

    static func offer(
        serverID: String = serverID, keyB64: String = keyB64, endpoint: String = "relay.example.test:443",
        useTLS: Bool = true, password: String? = nil
    ) -> ConnectionOffer {
        ConnectionOffer(
            serverID: serverID, daemonPublicKeyB64: keyB64,
            daemonPublicKey: Array(0..<32).map { UInt8($0) },
            relayEndpoint: endpoint, relayUseTLS: useTLS, minimumSecurityMode: .protected,
            password: password)
    }

    // MARK: Floor

    @Test func anOfferWithoutAPinStillGetsTheProtectedFloor() {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        var offer = Self.offer()
        #expect(pins.minimumSecurityMode(for: offer) == .protected)
        // Even when the offer itself says nothing about a minimum.
        offer.minimumSecurityMode = nil
        #expect(pins.minimumSecurityMode(for: offer) == .protected)
    }

    @Test func recordingAPinPersistsTheHostAndItsFloor() throws {
        let store = InMemoryRelayPinStore()
        let pins = RelayHostPins(store: store)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(pins.record(Self.offer(), at: date) == .newHost)
        let pin = try #require(pins.pin(serverID: Self.serverID))
        #expect(pin.daemonPublicKeyB64 == Self.keyB64)
        #expect(pin.minimumSecurityMode == .protected)
        #expect(pin.relayEndpoint == "relay.example.test:443")
        #expect(pin.relayUseTLS)
        #expect(pin.lastConnectedAt == date)
        #expect(pins.minimumSecurityMode(for: Self.offer()) == .protected)
    }

    @Test func recordingTheSameHostAgainIsUnchanged() {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        #expect(pins.record(Self.offer()) == .newHost)
        #expect(pins.record(Self.offer()) == .unchanged)
    }

    @Test func aDifferentDaemonKeyAtTheSameIdentityIsReported() {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        _ = pins.record(Self.offer())
        let change = pins.record(Self.offer(keyB64: Self.otherKeyB64))
        #expect(change == .daemonKeyChanged(previousB64: Self.keyB64))
        // The pin follows the newest key, still at the protected floor.
        #expect(pins.pin(serverID: Self.serverID)?.daemonPublicKeyB64 == Self.otherKeyB64)
        #expect(pins.pin(serverID: Self.serverID)?.minimumSecurityMode == .protected)
    }

    @Test func aStoredFloorIsNeverLoweredByALaterRecord() throws {
        // A pin written as protected, then a record whose offer claims nothing weaker can exist
        // today; the rule is expressed by the merge, so assert the merge keeps the pin's mode.
        let store = InMemoryRelayPinStore()
        store.save(
            RelayPinnedHost(
                serverID: Self.serverID, daemonPublicKeyB64: Self.keyB64,
                minimumSecurityMode: .protected, relayEndpoint: "old.test:443", relayUseTLS: true))
        let pins = RelayHostPins(store: store)
        var offer = Self.offer()
        offer.minimumSecurityMode = nil
        _ = pins.record(offer)
        #expect(try #require(pins.pin(serverID: Self.serverID)).minimumSecurityMode == .protected)
    }

    @Test func forgetRemovesThePin() {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        _ = pins.record(Self.offer())
        pins.forget(serverID: Self.serverID)
        #expect(pins.pin(serverID: Self.serverID) == nil)
        #expect(pins.pins().isEmpty)
        #expect(pins.record(Self.offer()) == .newHost)
    }

    // MARK: Secrets

    @Test func theSecretStoreRoundTripsAndEmptyRemoves() {
        let secrets = InMemoryRelaySecretStore()
        #expect(secrets.password(serverID: Self.serverID) == nil)
        secrets.savePassword("hunter2", serverID: Self.serverID)
        #expect(secrets.password(serverID: Self.serverID) == "hunter2")
        secrets.savePassword("", serverID: Self.serverID)
        #expect(secrets.password(serverID: Self.serverID) == nil)
    }

    // MARK: Endpoint

    @Test func theEndpointTakesTheOffersPassword() throws {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        let secrets = InMemoryRelaySecretStore()
        secrets.savePassword("stored", serverID: Self.serverID)

        let endpoint = try Self.offer(password: "from-link").makeEndpoint(secrets: secrets, pins: pins)
        #expect(endpoint.credential == .password("from-link"))
        #expect(endpoint.relay?.serverID == Self.serverID)
        #expect(endpoint.relay?.daemonPublicKeyB64 == Self.keyB64)
        #expect(endpoint.relay?.minimumSecurityMode == .protected)
        #expect(endpoint.url.absoluteString.contains("role=client"))
        #expect(endpoint.url.absoluteString.contains("serverId=srv_AAAAAAAAAAAA"))
    }

    @Test func aLinkWithoutAPasswordFallsBackToTheSecretStore() throws {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        let secrets = InMemoryRelaySecretStore()
        secrets.savePassword("stored", serverID: Self.serverID)

        let endpoint = try Self.offer().makeEndpoint(secrets: secrets, pins: pins)
        #expect(endpoint.credential == .password("stored"))
    }

    @Test func aLinkWithoutAnyPasswordCarriesNoCredential() throws {
        let pins = RelayHostPins(store: InMemoryRelayPinStore())
        let secrets = InMemoryRelaySecretStore()
        // An empty stored password is the same as none.
        secrets.savePassword("", serverID: Self.serverID)

        let endpoint = try Self.offer().makeEndpoint(secrets: secrets, pins: pins)
        #expect(endpoint.credential == nil)
    }

    @Test func theEndpointTakesTheFlooredModeFromThePin() throws {
        // A pin is the authority even if the offer is silent about its own minimum.
        let store = InMemoryRelayPinStore()
        store.save(
            RelayPinnedHost(
                serverID: Self.serverID, daemonPublicKeyB64: Self.keyB64,
                minimumSecurityMode: .protected, relayEndpoint: "a.test:443", relayUseTLS: true))
        let pins = RelayHostPins(store: store)
        var offer = Self.offer()
        offer.minimumSecurityMode = nil
        let endpoint = try offer.makeEndpoint(secrets: InMemoryRelaySecretStore(), pins: pins)
        #expect(endpoint.relay?.minimumSecurityMode == .protected)
    }

    // MARK: What R18 persists

    @Test func aPinEncodesWithoutAnySecret() throws {
        let pin = RelayPinnedHost(offer: Self.offer(password: "hunter2"))
        let encoded = try JSONEncoder().encode(pin)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("hunter2"))
        #expect(!json.contains("password"))
        let decoded = try JSONDecoder().decode(RelayPinnedHost.self, from: encoded)
        #expect(decoded == pin)
        #expect(decoded.minimumSecurityMode == .protected)
    }
}
