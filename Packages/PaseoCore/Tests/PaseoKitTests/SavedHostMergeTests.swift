import Foundation
import PaseoKit
import Testing

/// L2 Part B: one host per daemon. Fixture ids and keys only; nothing from a real daemon.
@Suite struct SavedHostMergeTests {
    private let fixtureKey = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    private let relayEndpoint = "fixture-relay:443"
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    private func relayRow(label: String = "srv_FIXTURE", connected: Date? = nil) -> SavedHost {
        SavedHost(
            label: label, url: "wss://fixture-relay:443/ws", lastConnectedAt: connected,
            serverID: "srv_FIXTURE", daemonPublicKeyB64: fixtureKey,
            relayEndpoint: relayEndpoint, relayUseTLS: true)
    }

    private func directRow(
        url: String = "ws://192.0.2.1:6767/ws", label: String = "mac", connected: Date? = nil,
        daemon: String? = "srv_FIXTURE"
    ) -> SavedHost {
        SavedHost(
            label: label, url: url, lastConnectedAt: connected, directServerID: daemon)
    }

    // MARK: merge

    @Test func mergeKeepsRelayIdentityAndAddsDirectURL() {
        let relay = relayRow(label: "Desk", connected: earlier)
        let direct = directRow(label: "mac", connected: later)
        let merged = SavedHostMerge.merge(direct: direct, into: relay)
        #expect(merged.id == relay.id)
        #expect(merged.serverID == "srv_FIXTURE")
        #expect(merged.identityKey == "relay:srv_FIXTURE")
        #expect(merged.daemonPublicKeyB64 == fixtureKey)
        #expect(merged.relayEndpoint == relayEndpoint)
        #expect(merged.relayUseTLS == true)
        #expect(merged.url == relay.url)
        #expect(merged.directURL == direct.url)
        #expect(merged.label == "Desk")
        #expect(merged.lastConnectedAt == later)
        #expect(merged.isRelay)
    }

    @Test func mergeTakesDirectLabelOnlyWhileRelayLabelIsDefault() {
        let defaultLabel = SavedHostMerge.merge(
            direct: directRow(label: "mac"), into: relayRow(label: "srv_FIXTURE"))
        #expect(defaultLabel.label == "mac")
        let renamed = SavedHostMerge.merge(
            direct: directRow(label: "mac"), into: relayRow(label: "Desk"))
        #expect(renamed.label == "Desk")
    }

    @Test func mergeKeepsLaterLastConnectedAtEitherWay() {
        let relayLater = SavedHostMerge.merge(
            direct: directRow(connected: earlier), into: relayRow(connected: later))
        #expect(relayLater.lastConnectedAt == later)
        let directLater = SavedHostMerge.merge(
            direct: directRow(connected: later), into: relayRow(connected: earlier))
        #expect(directLater.lastConnectedAt == later)
        let neither = SavedHostMerge.merge(direct: directRow(), into: relayRow())
        #expect(neither.lastConnectedAt == nil)
    }

    // MARK: Keychain rule

    @Test func passwordMovesOnlyWhenRelayHasNone() {
        #expect(
            SavedHostMerge.passwordMove(relayHasPassword: false, directHasPassword: true)
                == .moveDirectToRelay)
        #expect(
            SavedHostMerge.passwordMove(relayHasPassword: true, directHasPassword: true)
                == .keepRelay)
        #expect(
            SavedHostMerge.passwordMove(relayHasPassword: true, directHasPassword: false)
                == .keepRelay)
        #expect(
            SavedHostMerge.passwordMove(relayHasPassword: false, directHasPassword: false)
                == .keepRelay)
    }

    // MARK: connections and ids

    @Test func relayConnectionIDsFollowUpstreamScheme() {
        #expect(relayRow().connections.map(\.id) == ["relay:wss:fixture-relay:443"])
        var plain = relayRow()
        plain.relayUseTLS = false
        #expect(plain.connections.map(\.id) == ["relay:fixture-relay:443"])
        #expect(plain.connections.first?.kind == .relay)
        #expect(plain.connections.first?.endpoint == "fixture-relay:443")
    }

    @Test func directConnectionIDUsesNormalizedHostPort() {
        let direct = directRow(url: "ws://192.0.2.1:6767/ws")
        #expect(direct.connections == [
            SavedHostConnection(id: "direct:192.0.2.1:6767", kind: .direct, endpoint: "192.0.2.1:6767")
        ])
        let loopback = directRow(url: "ws://127.0.0.1:6767/ws")
        #expect(loopback.connections.map(\.id) == ["direct:localhost:6767"])
        let tls = directRow(url: "wss://fixture-host:6768/ws")
        #expect(tls.connections.map(\.id) == ["direct:fixture-host:6768"])
        let noPort = directRow(url: "ws://fixture-host/ws")
        #expect(noPort.connections.isEmpty)
    }

    @Test func mergedRelayRowHasRelayAndDirectConnections() {
        let merged = SavedHostMerge.merge(direct: directRow(), into: relayRow())
        #expect(merged.connections.map(\.id) == [
            "relay:wss:fixture-relay:443", "direct:192.0.2.1:6767",
        ])
        #expect(merged.connections.map(\.kind) == [.relay, .direct])
    }

    @Test func oldBlobWithoutDirectURLDecodesAndRoundTrips() throws {
        let json = #"""
        [{"id":"22222222-2222-2222-2222-222222222222","label":"srv_FIXTURE","url":"wss://fixture-relay:443/ws","serverID":"srv_FIXTURE","daemonPublicKeyB64":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=","relayEndpoint":"fixture-relay:443","relayUseTLS":true}]
        """#
        let hosts = try JSONDecoder().decode([SavedHost].self, from: Data(json.utf8))
        let host = try #require(hosts.first)
        #expect(host.directURL == nil)
        #expect(host.connections.map(\.id) == ["relay:wss:fixture-relay:443"])
        let back = try JSONDecoder().decode([SavedHost].self, from: JSONEncoder().encode(hosts))
        #expect(back == hosts)
    }

    @Test func mergedDirectURLSurvivesJSONRoundTrip() throws {
        let merged = SavedHostMerge.merge(direct: directRow(), into: relayRow())
        let back = try JSONDecoder().decode([SavedHost].self, from: JSONEncoder().encode([merged]))
        #expect(back == [merged])
        #expect(back.first?.directURL == "ws://192.0.2.1:6767/ws")
    }

    // MARK: mergePlan

    @Test func planPairsOneRelayWithOneDirectOfTheSameDaemon() throws {
        let relay = relayRow()
        let direct = directRow()
        let unrelated = directRow(url: "ws://192.0.2.9:6767/ws", daemon: "srv_OTHER")
        let plan = SavedHostDuplicates.mergePlan([unrelated, direct, relay])
        #expect(plan.count == 1)
        let step = try #require(plan.first)
        #expect(step.keep.id == relay.id)
        #expect(step.absorb.id == direct.id)
    }

    @Test func planAcceptsRelayAlreadyNamingTheSameDirectURL() {
        var relay = relayRow()
        relay.directURL = "ws://192.0.2.1:6767/ws"
        #expect(SavedHostDuplicates.mergePlan([relay, directRow()]).count == 1)
    }

    @Test func planSkipsRelayThatNamesADifferentDirectURL() {
        var relay = relayRow()
        relay.directURL = "ws://192.0.2.7:6767/ws"
        #expect(SavedHostDuplicates.mergePlan([relay, directRow()]).isEmpty)
    }

    @Test func twoDirectRowsForOneDaemonAreUntouched() {
        let first = directRow(url: "ws://192.0.2.1:6767/ws")
        let second = directRow(url: "ws://192.0.2.2:6767/ws")
        #expect(SavedHostDuplicates.mergePlan([first, second]).isEmpty)
        #expect(SavedHostDuplicates.mergePlan([relayRow(), first, second]).isEmpty)
        #expect(SavedHostDuplicates.groups([first, second]).count == 1)
    }

    @Test func twoRelayRowsForOneDaemonAreUntouched() {
        var other = relayRow()
        other.label = "second"
        other.lastConnectedAt = nil
        #expect(SavedHostDuplicates.mergePlan([relayRow(), other, directRow()]).isEmpty)
    }

    @Test func rowsWithoutDaemonIDAreNotPlanned() {
        #expect(SavedHostDuplicates.mergePlan([directRow(daemon: nil)]).isEmpty)
    }
}
