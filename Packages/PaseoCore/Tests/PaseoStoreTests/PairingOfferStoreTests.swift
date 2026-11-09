import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// R19: the pairing-offer slot on `HostSettingsStore`, over a hand-written fake response
/// (fake ids only — this suite never touches a real daemon).
@Suite @MainActor
struct PairingOfferStoreTests {
    private func serverInfo(features: [String: JSONValue]) throws -> ServerInfo {
        var info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self,
            from: Fixture.hostSettings("server_info")).payload
        info.features = features
        return info
    }

    @Test func loadsOfferWhenAdvertised() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(
            try serverInfo(features: ["daemonStatusRpc": .bool(true)]))
        #expect(store.supportsPairingOffer)
        client.onSend(DaemonGetPairingOfferRequest.self) { _ in
            DaemonGetPairingOfferRequest.Response(
                requestId: "r-1", url: "https://example.invalid/#offer=srv_FIXTURE",
                relayEnabled: true)
        }

        let loaded = await store.loadPairingOffer()

        #expect(loaded)
        #expect(
            store.pairingOfferState
                == .received(url: "https://example.invalid/#offer=srv_FIXTURE", relayEnabled: true))
        store.clearPairingOffer()
        #expect(store.pairingOfferState == .idle, "closing the page drops the credential")
    }

    @Test func relayDisabledOfferAsksForEnablement() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(
            try serverInfo(features: ["daemonStatusRpc": .bool(true)]))
        client.onSend(DaemonGetPairingOfferRequest.self) { _ in
            DaemonGetPairingOfferRequest.Response(requestId: "r-2", url: nil, relayEnabled: false)
        }
        _ = await store.loadPairingOffer()
        #expect(store.pairingOfferState == .received(url: "", relayEnabled: false))
    }

    @Test func ungatedDaemonNeverSendsTheRequest() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try serverInfo(features: [:]))
        let loaded = await store.loadPairingOffer()
        #expect(!loaded)
        #expect(store.pairingOfferState == .failed("This daemon cannot create a pairing link."))
        #expect(client.requests(DaemonGetPairingOfferRequest.self).isEmpty)
    }

    @Test func enableRelaySendsOnlyTheRelayPatch() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(
            try serverInfo(features: ["relayConfig": .bool(true)]))
        let response = try JSONDecoder().decode(
            SessionPayloadEnvelope<SetDaemonConfigRequest.Response>.self,
            from: Fixture.hostSettings("set_daemon_config_response")).payload
        client.onSend(SetDaemonConfigRequest.self) { _ in response }

        let enabled = await store.enableRelay()

        #expect(enabled)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        #expect(sent.config.relay?.enabled == true)
        #expect(sent.config.resumePrompt == nil, "only the relay field goes out")
    }

    @Test func enableRelayIsGated() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try serverInfo(features: [:]))
        let enabled = await store.enableRelay()
        #expect(!enabled)
        #expect(store.error == "This daemon cannot be configured for relay.")
        #expect(client.requests(SetDaemonConfigRequest.self).isEmpty)
    }
}
