import Foundation
import PaseoKit
import Testing

@testable import PaseoStore

/// M20: the pure `paseo://` parser. Every link here is synthetic (`srv_FIXTURE`, generated key
/// bytes), never a real pairing link or daemon identity.
@Suite struct DeepLinkTests {
    private static let serverID = "srv_FIXTURE"
    private static let agentID = "agent-1"
    private static let workspaceID = "workspace-1"

    /// A throwaway 32-byte X25519 public key. Generated here, never a real one.
    private static var fixtureKeyB64: String {
        Data((0..<32).map { UInt8($0) }).base64EncodedString()
    }

    private static var fixtureKey: String { fixtureKeyB64 }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func offerLink(serverID: String = serverID) -> String {
        let json = """
            {"v":2,"serverId":"\(serverID)","daemonPublicKeyB64":"\(fixtureKey)",
            "relay":{"endpoint":"relay.example:443"},"minimumSecurityMode":"protected"}
            """
        return "https://app.example/#offer=\(base64URL(json))"
    }

    private static func relayLink() -> String {
        "relay://relay.example:443/\(serverID)?key=\(fixtureKey)&ssl=true&security=protected"
    }

    // MARK: Offer links (the credential shape)

    @Test func parsesOfferFragment() throws {
        let link = try #require(DeepLink(string: Self.offerLink()))
        guard case .offer(let offer) = link else {
            Issue.record("expected an offer")
            return
        }
        #expect(offer.serverID == Self.serverID)
        #expect(offer.relayEndpoint == "relay.example:443")
        #expect(offer.requiresProtectedSecurity)
        #expect(link.isNavigation == false)
        #expect(link.targetServerID == nil)
    }

    @Test func parsesRelayURIAndConnectFragment() throws {
        let relay = try #require(DeepLink(string: Self.relayLink()))
        guard case .offer(let relayOffer) = relay else {
            Issue.record("expected a relay offer")
            return
        }
        #expect(relayOffer.serverID == Self.serverID)

        let connect = try #require(
            DeepLink(string: "https://app.example/#connect=\(Self.relayLink())"))
        guard case .offer(let connectOffer) = connect else {
            Issue.record("expected a connect offer")
            return
        }
        #expect(connectOffer.serverID == Self.serverID)
    }

    @Test func malformedOfferIsIgnored() {
        // The credential is never echoed or partially accepted.
        #expect(DeepLink(string: "https://app.example/#offer=not-base64!") == nil)
        #expect(DeepLink(string: "https://app.example/#offer=") == nil)
        #expect(DeepLink(string: "relay://relay.example:443/") == nil)
        #expect(DeepLink(string: "relay://user:pass@relay.example:443/srv_FIXTURE?key=AAAA") == nil)
    }

    // MARK: Agent routes

    @Test func parsesAgentRoute() throws {
        for raw in [
            "paseo://h/\(Self.serverID)/agent/\(Self.agentID)",
            "paseo:/h/\(Self.serverID)/agent/\(Self.agentID)",
        ] {
            let link = try #require(DeepLink(string: raw))
            #expect(link == .agent(serverID: Self.serverID, agentID: Self.agentID))
            #expect(link.targetServerID == Self.serverID)
            #expect(link.isNavigation)
        }
    }

    @Test func decodesPercentEncodedAgentRoute() throws {
        // Upstream `agent-deep-link.test.ts:13-17`: ids are encoded per segment.
        let link = try #require(DeepLink(string: "paseo://h/server%2Fmain/agent/agent%20123"))
        #expect(link == .agent(serverID: "server/main", agentID: "agent 123"))
    }

    @Test func rejectsAgentRoutesOutsideTheExactShape() {
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/agent") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/agent/\(Self.agentID)?message=hi") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/agent/\(Self.agentID)#x") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/agent/\(Self.agentID)/extra") == nil)
        #expect(DeepLink(string: "https://h/\(Self.serverID)/agent/\(Self.agentID)") == nil)
        #expect(DeepLink(string: "paseo://app/h/\(Self.serverID)/agent/\(Self.agentID)") == nil)
        #expect(DeepLink(string: "paseo://h:1234/\(Self.serverID)/agent/\(Self.agentID)") == nil)
    }

    // MARK: Workspace routes

    @Test func parsesWorkspaceRoute() throws {
        let link = try #require(
            DeepLink(string: "paseo://h/\(Self.serverID)/workspace/\(Self.workspaceID)"))
        #expect(
            link
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID, open: nil))
    }

    @Test func decodesWorkspaceOpenIntents() throws {
        func workspace(_ open: String) throws -> DeepLink {
            try #require(
                DeepLink(
                    string:
                        "paseo://h/\(Self.serverID)/workspace/\(Self.workspaceID)?open=\(open)"))
        }

        #expect(
            try workspace("agent%3A\(Self.agentID)")
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID,
                    open: .agent(Self.agentID)))
        #expect(
            try workspace("terminal%3Aterm-1")
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID,
                    open: .terminal("term-1")))
        #expect(
            try workspace("draft%3Adraft_1")
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID,
                    open: .draft("draft_1")))

        let filePath = "src/My File.swift"
        let fileIntent = "file%3A\(Self.base64URL(filePath))"
        #expect(
            try workspace(fileIntent)
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID,
                    open: .file(filePath)))

        let setupID = "workspace/config"
        let setupIntent = "setup%3Ab64_\(Self.base64URL(setupID))"
        #expect(
            try workspace(setupIntent)
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID,
                    open: .setup(setupID)))

        // An intent we cannot decode leaves the workspace open, not the whole link dead.
        #expect(
            try workspace("nonsense")
                == .workspace(
                    serverID: Self.serverID, workspaceID: Self.workspaceID, open: nil))
    }

    @Test func decodesBase64PrefixedWorkspaceIDs() throws {
        let workspaceID = "path/with/slash"
        let link = try #require(
            DeepLink(
                string:
                    "paseo://h/\(Self.serverID)/workspace/b64_\(Self.base64URL(workspaceID))"))
        #expect(
            link
                == .workspace(
                    serverID: Self.serverID, workspaceID: workspaceID, open: nil))
    }

    @Test func rejectsMalformedWorkspaceRoutes() {
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/workspace") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/workspace/\(Self.workspaceID)/x") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/workspace/") == nil)
    }

    // MARK: Host root, open project, unsupported routes

    @Test func parsesHostRootAndOpenProject() throws {
        #expect(
            try #require(DeepLink(string: "paseo://h/\(Self.serverID)"))
                == .host(serverID: Self.serverID))
        #expect(
            try #require(DeepLink(string: "paseo://h/\(Self.serverID)/open-project"))
                == .openProject(serverID: Self.serverID))
        #expect(
            try #require(DeepLink(string: "paseo://open-project"))
                == .openProject(serverID: nil))
    }

    @Test func recognisesUnsupportedScreens() throws {
        let cases: [(String, String)] = [
            ("paseo://h/\(Self.serverID)/sessions", "sessions"),
            ("paseo://h/\(Self.serverID)/settings", "settings"),
            ("paseo://h/\(Self.serverID)/plugin/owner.slug/screen", "plugin"),
            ("paseo://sessions", "sessions"),
            ("paseo://settings", "settings"),
            ("paseo://new", "new"),
            ("paseo://schedules", "schedules"),
            ("paseo://welcome", "welcome"),
        ]
        for (raw, screen) in cases {
            let link = try #require(DeepLink(string: raw), "expected \(screen)")
            #expect(link == .unsupported(screen))
            #expect(link.isNavigation == false)
        }
    }

    @Test func ignoresUnknownAndMalformedLinks() {
        #expect(DeepLink(string: "") == nil)
        #expect(DeepLink(string: "   ") == nil)
        #expect(DeepLink(string: "not a url") == nil)
        #expect(DeepLink(string: "paseo://whatever/thing") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/unknown") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/open-project/extra") == nil)
        #expect(DeepLink(string: "paseo://h//agent/\(Self.agentID)") == nil)
        #expect(DeepLink(string: "paseo://h/\(Self.serverID)/agent/%ZZ") == nil)
        if let plain = URL(string: "https://example.com/hello") {
            #expect(DeepLink(url: plain) == nil)
        }
    }

    // MARK: Host resolution

    private func host(
        _ label: String, serverID: String?, local: Bool = false, current: Bool = false
    ) -> DeepLinkHost {
        DeepLinkHost(
            id: UUID(), label: label, serverID: serverID, url: "ws://example:6767/ws",
            isRelay: serverID != nil, isCurrent: current, isLocal: local)
    }

    @Test func resolvesTheNamedHost() {
        let saved = [host("A", serverID: "srv_A"), host("B", serverID: "srv_B")]
        let link = DeepLink.agent(serverID: "srv_B", agentID: "agent-1")

        let resolution = DeepLinkRouter.resolveHost(for: link, savedHosts: saved)
        guard case .target(let target) = resolution else {
            Issue.record("expected a target")
            return
        }
        #expect(target.serverID == "srv_B")
    }

    @Test func unknownNamedHostIsReported() {
        let saved = [host("A", serverID: "srv_A")]
        let resolution = DeepLinkRouter.resolveHost(
            for: .workspace(serverID: "srv_MISSING", workspaceID: "ws", open: nil),
            savedHosts: saved)
        #expect(resolution == .unknownHost("srv_MISSING"))
    }

    @Test func hostlessOpenProjectUsesTheOnlyHostOrAsks() {
        let one = [host("A", serverID: "srv_A")]
        let link = DeepLink.openProject(serverID: nil)
        let single = DeepLinkRouter.resolveHost(for: link, savedHosts: one)
        guard case .target(let target) = single else {
            Issue.record("expected the only host")
            return
        }
        #expect(target.serverID == "srv_A")

        let many = [host("A", serverID: "srv_A"), host("Local", serverID: nil, local: true)]
        let choice = DeepLinkRouter.resolveHost(for: link, savedHosts: many)
        guard case .chooseHost(let choices) = choice else {
            Issue.record("expected a chooser")
            return
        }
        #expect(choices.map(\.label) == ["Local", "A"], "upstream orders local first")

        #expect(DeepLinkRouter.resolveHost(for: link, savedHosts: []) == .noHosts)
    }

    @Test func offersNeverAskForAHost() {
        let link = DeepLink.offer(
            ConnectionOffer(
                serverID: "srv_A", daemonPublicKeyB64: Self.fixtureKey,
                daemonPublicKey: Array(0..<32).map { UInt8($0) },
                relayEndpoint: "relay.example:443", relayUseTLS: true))
        #expect(DeepLinkRouter.resolveHost(for: link, savedHosts: []) == nil)
    }

    @Test func chooserSearchesLabelAndServerID() {
        let local = host("Laptop", serverID: "srv_local", local: true)
        let remote = host("Build box", serverID: "srv_build")

        #expect(DeepLinkHost.localFirst([remote, local]).map(\.label) == ["Laptop", "Build box"])
        #expect(DeepLinkHost.localFirst([local, remote]).map(\.label) == ["Laptop", "Build box"])

        #expect(DeepLinkHost.matches(remote, query: " build "))
        #expect(DeepLinkHost.matches(remote, query: "SRV_BUILD"))
        #expect(!DeepLinkHost.matches(remote, query: "laptop"))
        #expect(DeepLinkHost.matches(remote, query: ""))
    }

    @Test func savedHostDescriptorUsesTheDaemonIdentity() {
        let saved = SavedHost(
            label: "Desk", url: "wss://relay.example/ws?serverId=srv_A", serverID: "srv_A",
            daemonPublicKeyB64: Self.fixtureKey, relayEndpoint: "relay.example:443",
            relayUseTLS: true)
        let descriptor = DeepLinkHost(saved: saved, isCurrent: true)
        #expect(descriptor.serverID == "srv_A")
        #expect(descriptor.detail == "srv_A")
        #expect(descriptor.isRelay)
        #expect(descriptor.isCurrent)
        #expect(!descriptor.isLocal)

        let direct = SavedHost(label: "Local", url: "ws://127.0.0.1:6767/ws")
        #expect(DeepLinkHost(saved: direct, isCurrent: false).isLocal)
        #expect(DeepLinkHost(saved: direct, isCurrent: false).detail == "ws://127.0.0.1:6767/ws")
        // A direct host learns its daemon identity from the live handshake only.
        let live = DeepLinkHost(saved: direct, isCurrent: true, liveServerID: "srv_LIVE")
        #expect(live.serverID == "srv_LIVE")
        #expect(live.detail == "srv_LIVE")
        #expect(DeepLinkHost(saved: direct, isCurrent: false, liveServerID: "srv_LIVE").serverID == "srv_LIVE")
    }
}
