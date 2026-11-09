import Foundation
import PaseoKit
import Testing

/// M20b: direct hosts learn their daemon `serverId` from `server_info`. Fixture ids only.
@Suite struct DirectHostServerIDTests {
    private let oldDirectJSON = #"""
        [{"id":"11111111-1111-1111-1111-111111111111","label":"mac","url":"ws://192.0.2.1:6767/ws","lastConnectedAt":778500000.0}]
        """#

    private let oldRelayJSON = #"""
        [{"id":"22222222-2222-2222-2222-222222222222","label":"srv_FIXTURE","url":"wss://fixture-relay:443/ws","lastConnectedAt":778500000.0,"serverID":"srv_FIXTURE","daemonPublicKeyB64":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=","relayEndpoint":"fixture-relay:443","relayUseTLS":true}]
        """#

    @Test func preM20bDirectBlobMigratesWithNilDirectID() throws {
        let hosts = try JSONDecoder().decode([SavedHost].self, from: Data(oldDirectJSON.utf8))
        let host = try #require(hosts.first)
        #expect(host.directServerID == nil)
        #expect(host.serverID == nil)
        #expect(host.daemonServerID == nil)
        #expect(!host.isRelay)
        #expect(host.identityKey == "ws://192.0.2.1:6767/ws")
        // The migrated row re-encodes and decodes identically, and still carries its id/URL.
        let back = try JSONDecoder().decode(
            [SavedHost].self, from: try JSONEncoder().encode(hosts))
        #expect(back == hosts)
        #expect(back.first?.id.uuidString == "11111111-1111-1111-1111-111111111111")
        #expect(back.first?.url == "ws://192.0.2.1:6767/ws")
    }

    @Test func preM20bRelayBlobDoesNotGainADirectID() throws {
        let hosts = try JSONDecoder().decode([SavedHost].self, from: Data(oldRelayJSON.utf8))
        let host = try #require(hosts.first)
        #expect(host.isRelay)
        #expect(host.serverID == "srv_FIXTURE")
        #expect(host.directServerID == nil)
        #expect(host.daemonServerID == "srv_FIXTURE")
    }

    @Test func learningIsAdditiveAndThenStable() {
        var host = SavedHost(label: "mac", url: "ws://192.0.2.1:6767/ws")
        #expect(host.learnDirectServerID(nil) == .unchanged)
        #expect(host.learnDirectServerID("   ") == .unchanged)
        #expect(host.directServerID == nil)

        #expect(host.learnDirectServerID(" srv_DIRECT ") == .learned("srv_DIRECT"))
        #expect(host.directServerID == "srv_DIRECT")
        #expect(host.daemonServerID == "srv_DIRECT")
        #expect(host.identityKey == "ws://192.0.2.1:6767/ws")

        #expect(host.learnDirectServerID("srv_DIRECT") == .unchanged)
        #expect(host.directServerID == "srv_DIRECT")
    }

    @Test func relayRowsNeverGainADirectID() {
        var relay = SavedHost(
            label: "srv_FIXTURE", url: "wss://fixture-relay:443/ws", serverID: "srv_FIXTURE",
            daemonPublicKeyB64: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
            relayEndpoint: "fixture-relay:443", relayUseTLS: true)
        #expect(relay.learnDirectServerID("srv_FIXTURE") == .unchanged)
        #expect(relay.learnDirectServerID("srv_OTHER") == .unchanged)
        #expect(relay.directServerID == nil)
        #expect(relay.daemonServerID == "srv_FIXTURE")
    }

    @Test func differentIDIsReportedNotSilent() {
        var host = SavedHost(
            label: "mac", url: "ws://192.0.2.1:6767/ws", directServerID: "srv_OLD")
        #expect(
            host.learnDirectServerID("srv_NEW")
                == .replaced(previous: "srv_OLD", current: "srv_NEW"))
        #expect(host.directServerID == "srv_NEW")
        // Learning never touches relay-only fields.
        #expect(host.serverID == nil)
        #expect(!host.isRelay)
    }

    @Test func learnedIDSurvivesJSONRoundTrip() throws {
        var host = SavedHost(label: "mac", url: "ws://192.0.2.1:6767/ws")
        #expect(host.learnDirectServerID("srv_DIRECT") == .learned("srv_DIRECT"))
        let data = try JSONEncoder().encode([host])
        let back = try JSONDecoder().decode([SavedHost].self, from: data)
        #expect(back == [host])
        #expect(back.first?.directServerID == "srv_DIRECT")
    }

    @Test func sameDaemonDetectionUsesEitherIdentity() {
        let direct = SavedHost(
            label: "mac", url: "ws://192.0.2.1:6767/ws", directServerID: "srv_SAME")
        let relay = SavedHost(
            label: "srv_SAME", url: "wss://fixture-relay:443/ws", serverID: "srv_SAME",
            daemonPublicKeyB64: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
            relayEndpoint: "fixture-relay:443", relayUseTLS: true)
        let other = SavedHost(
            label: "other", url: "ws://192.0.2.2:6767/ws", directServerID: "srv_OTHER")
        let unknown = SavedHost(label: "unknown", url: "ws://192.0.2.3:6767/ws")
        #expect(direct.isSameDaemon(as: relay))
        #expect(relay.isSameDaemon(as: direct))
        #expect(!direct.isSameDaemon(as: other))
        #expect(!direct.isSameDaemon(as: unknown))
        #expect(!unknown.isSameDaemon(as: unknown))
    }

    @Test func duplicatesGroupDirectAndRelayRowsForOneDaemon() throws {
        let direct = SavedHost(
            label: "mac", url: "ws://192.0.2.1:6767/ws", directServerID: "srv_SAME")
        let relay = SavedHost(
            label: "srv_SAME", url: "wss://fixture-relay:443/ws", serverID: "srv_SAME",
            daemonPublicKeyB64: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
            relayEndpoint: "fixture-relay:443", relayUseTLS: true)
        let other = SavedHost(
            label: "other", url: "ws://192.0.2.2:6767/ws", directServerID: "srv_OTHER")
        let unknown = SavedHost(label: "unknown", url: "ws://192.0.2.3:6767/ws")

        let groups = SavedHostDuplicates.groups([other, direct, unknown, relay])
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.map(\.id) == [direct.id, relay.id])
        #expect(SavedHostDuplicates.serverIDs([other, direct, unknown, relay]) == ["srv_SAME"])
    }

    @Test func duplicateDetectionIgnoresUniqueAndKnownIDlessRows() {
        let a = SavedHost(label: "a", url: "ws://192.0.2.1:6767/ws", directServerID: "srv_A")
        let b = SavedHost(label: "b", url: "ws://192.0.2.2:6767/ws", directServerID: "srv_B")
        let unknown = SavedHost(label: "c", url: "ws://192.0.2.3:6767/ws")
        #expect(SavedHostDuplicates.groups([a, b, unknown]).isEmpty)
        #expect(SavedHostDuplicates.serverIDs([a, b, unknown]).isEmpty)
    }

    @Test func duplicateGroupsAreOrderedByServerID() {
        let first = SavedHost(label: "a1", url: "ws://192.0.2.1:6767/ws", directServerID: "srv_B")
        let second = SavedHost(label: "a2", url: "ws://192.0.2.2:6767/ws", directServerID: "srv_B")
        let third = SavedHost(label: "b1", url: "ws://192.0.2.3:6767/ws", directServerID: "srv_A")
        let fourth = SavedHost(label: "b2", url: "ws://192.0.2.4:6767/ws", directServerID: "srv_A")
        #expect(
            SavedHostDuplicates.serverIDs([first, second, third, fourth]) == ["srv_A", "srv_B"])
    }
}
