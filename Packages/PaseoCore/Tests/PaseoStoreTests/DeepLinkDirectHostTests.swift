import Foundation
import PaseoKit
import PaseoStore
import Testing

/// M20b: a saved direct host that has connected once carries a stored daemon id, so deep
/// links find it without the live session. Fixture ids and endpoints only.
@Suite struct DeepLinkDirectHostTests {
    private let savedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
    private let directServerID = "srv_DIRECT"

    private func directHost(isCurrent: Bool = false, learned: Bool = true) -> SavedHost {
        SavedHost(
            id: savedID, label: "studio", url: "ws://192.0.2.10:6767/ws",
            lastConnectedAt: Date(timeIntervalSince1970: 778_500_000),
            directServerID: learned ? directServerID : nil)
    }

    @Test func storedDirectIDMatchesAnAgentLinkWithoutALiveSession() throws {
        let link = try #require(
            DeepLink(string: "paseo://h/\(directServerID)/agent/agent_FIXTURE"))
        let resolution = DeepLinkRouter.resolveHost(
            for: link, savedHosts: [DeepLinkHost(saved: directHost(), isCurrent: false)])
        guard case .target(let host) = resolution else {
            Issue.record("expected the saved direct host")
            return
        }
        #expect(host.id == savedID)
        #expect(host.serverID == directServerID)
        #expect(!host.isRelay)
        #expect(!host.isCurrent)
    }

    @Test func storedDirectIDMatchesWorkspaceAndHostLinks() throws {
        let saved = DeepLinkHost(saved: directHost(), isCurrent: false)
        for raw in [
            "paseo://h/\(directServerID)/workspace/ws_FIXTURE",
            "paseo://h/\(directServerID)",
        ] {
            let link = try #require(DeepLink(string: raw))
            #expect(DeepLinkRouter.resolveHost(for: link, savedHosts: [saved]) == .target(saved))
        }
    }

    @Test func aDifferentServerIDIsStillUnknown() throws {
        let link = try #require(
            DeepLink(string: "paseo://h/srv_OTHER/agent/agent_FIXTURE"))
        #expect(
            DeepLinkRouter.resolveHost(
                for: link, savedHosts: [DeepLinkHost(saved: directHost(), isCurrent: false)])
                == .unknownHost("srv_OTHER"))
    }

    @Test func aNeverConnectedDirectHostHasNoIdentity() throws {
        let unlearned = DeepLinkHost(
            saved: directHost(learned: false), isCurrent: false)
        #expect(unlearned.serverID == nil)
        #expect(unlearned.detail == "ws://192.0.2.10:6767/ws")
        let link = try #require(
            DeepLink(string: "paseo://h/\(directServerID)/agent/agent_FIXTURE"))
        #expect(
            DeepLinkRouter.resolveHost(for: link, savedHosts: [unlearned])
                == .unknownHost(directServerID))
    }

    @Test func directAndRelayRowsBothMatchTheSameLink() throws {
        // Detection, not merging: both saved rows are candidates for the same daemon.
        let relay = SavedHost(
            label: "studio relay", url: "wss://fixture-relay:443/ws", serverID: directServerID,
            daemonPublicKeyB64: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
            relayEndpoint: "fixture-relay:443", relayUseTLS: true)
        let hosts = [
            DeepLinkHost(saved: directHost(), isCurrent: false),
            DeepLinkHost(saved: relay, isCurrent: false),
        ]
        #expect(SavedHostDuplicates.serverIDs([directHost(), relay]) == [directServerID])
        let link = try #require(
            DeepLink(string: "paseo://h/\(directServerID)/agent/agent_FIXTURE"))
        // First match wins for routing; the list still renders both.
        #expect(DeepLinkRouter.resolveHost(for: link, savedHosts: hosts) == .target(hosts[0]))
    }

    @Test func learnedIDLiftsLocalOrderingForAServerIDPrefixedID() {
        // A local daemon may report `local:…`; that still counts as local even when the
        // endpoint is not loopback (e.g. a Tailscale address).
        let host = SavedHost(
            label: "studio", url: "ws://100.64.0.2:6767/ws",
            directServerID: "local:studio")
        #expect(DeepLinkHost(saved: host, isCurrent: false).isLocal)
    }
}
