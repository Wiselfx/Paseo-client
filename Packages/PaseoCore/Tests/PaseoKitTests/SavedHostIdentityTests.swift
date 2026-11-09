import Foundation
import PaseoKit
import Testing

/// R18: saved-host identity and the host-confirmation rules. Only synthetic keys exist
/// here — never a real daemon's.
@Suite struct SavedHostIdentityTests {
    private func offer(keySeed byte: UInt8, endpoint: String = "fixture-relay:443") -> ConnectionOffer {
        let key = [UInt8](repeating: byte, count: 32)
        return ConnectionOffer(
            serverID: "srv_fixture",
            daemonPublicKeyB64: Data(key).base64EncodedString(),
            daemonPublicKey: key,
            relayEndpoint: endpoint, relayUseTLS: true)
    }

    @Test func relayIdentityKeysOnServerID() {
        let offer = self.offer(keySeed: 1)
        let host = SavedHost(
            label: "srv_fixture", url: "wss://fixture-relay:443/ws",
            serverID: offer.serverID, daemonPublicKeyB64: offer.daemonPublicKeyB64,
            relayEndpoint: offer.relayEndpoint, relayUseTLS: true)
        #expect(host.isRelay)
        #expect(host.identityKey == "relay:srv_fixture")
        let direct = SavedHost(label: "mac", url: "ws://192.0.2.1:6767/ws")
        #expect(!direct.isRelay)
        #expect(direct.identityKey == "ws://192.0.2.1:6767/ws")
    }

    @Test func oldFormatBlobMigratesWithRelayFieldsNil() throws {
        let json = #"""
        [{"id":"11111111-1111-1111-1111-111111111111","label":"mac","url":"ws://192.0.2.1:6767/ws","lastConnectedAt":778500000.0}]
        """#
        let hosts = try JSONDecoder().decode([SavedHost].self, from: Data(json.utf8))
        #expect(hosts.count == 1)
        let host = try #require(hosts.first)
        #expect(host.id.uuidString == "11111111-1111-1111-1111-111111111111")
        #expect(host.label == "mac")
        #expect(host.url == "ws://192.0.2.1:6767/ws")
        #expect(host.lastConnectedAt != nil)
        #expect(host.serverID == nil)
        #expect(host.daemonPublicKeyB64 == nil)
        #expect(host.identityKey == "ws://192.0.2.1:6767/ws")
        // And the migrated host re-encodes and decodes identically.
        let data = try JSONEncoder().encode(hosts)
        let back = try JSONDecoder().decode([SavedHost].self, from: data)
        #expect(back == hosts)
    }

    @Test func fingerprintGroupsOfFourAndTruncatesLongKeys() {
        #expect(HostConfirmation.keyFingerprint("abcd1234") == "abcd 1234")
        #expect(HostConfirmation.keyFingerprint("aBc9-o!x@z") == "aBc9 oxz")
        let long = HostConfirmation.keyFingerprint("abcdefghijklmnopqrstuvwxyz0123456789ABCD")
        #expect(long == "abcd efgh … 6789 ABCD")
    }

    @Test func newHostAsksExactMatchDoesNot() {
        let offer = self.offer(keySeed: 7)
        #expect(HostConfirmation.confirmationKind(offer: offer, savedHosts: []) == .newHost)
        let saved = SavedHost(
            label: "srv_fixture", url: "wss://fixture-relay:443/ws",
            serverID: offer.serverID, daemonPublicKeyB64: offer.daemonPublicKeyB64,
            relayEndpoint: offer.relayEndpoint, relayUseTLS: true)
        #expect(HostConfirmation.confirmationKind(offer: offer, savedHosts: [saved]) == nil)
    }

    @Test func changedKeyOrEndpointAsksChanged() {
        let offer = self.offer(keySeed: 7)
        var saved = SavedHost(
            label: "srv_fixture", url: "wss://fixture-relay:443/ws",
            serverID: offer.serverID,
            daemonPublicKeyB64: Data([UInt8](repeating: 9, count: 32)).base64EncodedString(),
            relayEndpoint: offer.relayEndpoint, relayUseTLS: true)
        #expect(
            HostConfirmation.confirmationKind(offer: offer, savedHosts: [saved])
                == .changedConnection)
        saved.daemonPublicKeyB64 = offer.daemonPublicKeyB64
        saved.relayEndpoint = "fixture-relay:8443"
        #expect(
            HostConfirmation.confirmationKind(offer: offer, savedHosts: [saved])
                == .changedConnection)
        // A direct host with the same serverID string is still a new host: identity is
        // the daemon identity, and direct entries carry none.
        let direct = SavedHost(label: "mac", url: "ws://192.0.2.1:6767/ws")
        #expect(HostConfirmation.confirmationKind(offer: offer, savedHosts: [direct]) == .newHost)
    }
}
