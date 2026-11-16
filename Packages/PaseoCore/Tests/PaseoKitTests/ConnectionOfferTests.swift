import Foundation
import Testing
@testable import PaseoKit

/// R16: pairing-offer parsing. Every rejection rule in `docs/research/11-relay-pairing.md` §3 and
/// upstream `connection-offer.ts` / `daemon-endpoints.ts` has a case here.
///
/// All keys and ids are invented for the test; nothing from a real host appears.
@Suite struct ConnectionOfferTests {
    /// Standard base64 of the bytes 0x00…0x1F, i.e. a 32-byte X25519 public key.
    static let keyB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    static let serverID = "srv_AAAAAAAAAAAA"

    // MARK: Builders

    static func offerJSON(
        v: Int = 2, serverID: String? = serverID, keyB64: String? = keyB64,
        endpoint: String? = "relay.example.test:443", useTLS: Bool? = nil,
        security: String? = nil
    ) -> String {
        var relay: [String] = []
        if let endpoint { relay.append("\"endpoint\":\"\(endpoint)\"") }
        if let useTLS { relay.append("\"useTls\":\(useTLS)") }
        var fields: [String] = ["\"v\":\(v)"]
        if let serverID { fields.append("\"serverId\":\"\(serverID)\"") }
        if let keyB64 { fields.append("\"daemonPublicKeyB64\":\"\(keyB64)\"") }
        fields.append("\"relay\":{\(relay.joined(separator: ","))}")
        if let security { fields.append("\"minimumSecurityMode\":\"\(security)\"") }
        return "{\(fields.joined(separator: ","))}"
    }

    static func base64URL(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func link(json: String) -> String {
        "https://app.example.test/#offer=" + base64URL(json)
    }

    // MARK: #offer= happy paths

    @Test func parsesAProtectedOffer() throws {
        let offer = try ConnectionOffer(
            link: Self.link(json: Self.offerJSON(useTLS: true, security: "protected")))
        #expect(offer.serverID == Self.serverID)
        #expect(offer.daemonPublicKeyB64 == Self.keyB64)
        #expect(offer.daemonPublicKey == Array(0..<32).map { UInt8($0) })
        #expect(offer.relayEndpoint == "relay.example.test:443")
        #expect(offer.relayUseTLS)
        #expect(offer.minimumSecurityMode == .protected)
        #expect(offer.requiresProtectedSecurity)
        #expect(offer.password == nil)
    }

    @Test func parsesAnOfferWithoutTheSecurityPin() throws {
        let offer = try ConnectionOffer(link: Self.link(json: Self.offerJSON(useTLS: false)))
        #expect(offer.minimumSecurityMode == nil)
        #expect(offer.requiresProtectedSecurity == false)
        #expect(offer.relayUseTLS == false)
    }

    @Test func surroundingWhitespaceAndAppPrefixesAreTolerated() throws {
        let json = Self.offerJSON(useTLS: true)
        let encoded = Self.base64URL(json)
        for link in [
            "  https://app.example.test/#offer=\(encoded)\n",
            "#offer=\(encoded)",
            "HTTPS://APP.example.test/pair?x=1#offer=\(encoded)  ",
        ] {
            #expect(try ConnectionOffer(link: link).serverID == Self.serverID)
        }
    }

    @Test func useTLSDefaultsFromThePort() throws {
        #expect(try ConnectionOffer(link: Self.link(json: Self.offerJSON(endpoint: "a.test:443")))
            .relayUseTLS)
        #expect(try ConnectionOffer(link: Self.link(json: Self.offerJSON(endpoint: "a.test:80")))
            .relayUseTLS == false)
        // An explicit value wins over the port heuristic.
        #expect(try ConnectionOffer(link: Self.link(json: Self.offerJSON(endpoint: "a.test:443", useTLS: false)))
            .relayUseTLS == false)
        #expect(try ConnectionOffer(link: Self.link(json: Self.offerJSON(endpoint: "a.test:80", useTLS: true)))
            .relayUseTLS)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let json = "{\"v\":2,\"futureField\":{\"nested\":[1,2]},"
            + "\"serverId\":\"\(Self.serverID)\",\"daemonPublicKeyB64\":\"\(Self.keyB64)\","
            + "\"relay\":{\"endpoint\":\"a.test:443\",\"useTls\":true,\"extra\":null}}"
        let offer = try ConnectionOffer(link: Self.link(json: json))
        #expect(offer.serverID == Self.serverID)
        #expect(offer.relayUseTLS)
    }

    @Test func ipv6EndpointsKeepTheirBrackets() throws {
        let offer = try ConnectionOffer(
            link: Self.link(json: Self.offerJSON(endpoint: "[2001:db8::1]:8443", useTLS: true)))
        #expect(offer.relayEndpoint == "[2001:db8::1]:8443")
        #expect(try offer.relayWebSocketURL().absoluteString
            == "wss://[2001:db8::1]:8443/ws?serverId=\(Self.serverID)&role=client&v=2")
    }

    // MARK: #offer= rejections

    @Test func aLinkWithoutAnOfferFragmentIsRefused() {
        for link in ["", "   ", "https://app.example.test/pair", "#offer", "relay:/nope"] {
            #expect(throws: ConnectionOfferError.missingOfferFragment) {
                _ = try ConnectionOffer(link: link)
            }
        }
    }

    @Test func anEmptyOfferPayloadIsRefused() {
        for link in ["https://app.example.test/#offer=", "https://app.example.test/#offer=   "] {
            #expect(throws: ConnectionOfferError.emptyOfferPayload) {
                _ = try ConnectionOffer(link: link)
            }
        }
    }

    @Test func aNonBase64OfferPayloadIsRefused() {
        for payload in ["not base64!!", "AAAAA", "ab+/="] {
            #expect(throws: ConnectionOfferError.invalidBase64) {
                _ = try ConnectionOffer(link: "https://app.example.test/#offer=\(payload)")
            }
        }
    }

    @Test func aPayloadThatIsNotJSONIsRefused() {
        #expect(throws: ConnectionOfferError.malformedOffer) {
            _ = try ConnectionOffer(link: Self.link(json: "not json"))
        }
        #expect(throws: ConnectionOfferError.malformedOffer) {
            _ = try ConnectionOffer(link: Self.link(json: "[1,2,3]"))
        }
    }

    @Test func aMalformedPayloadLosesOneFieldAtATime() {
        let cases: [(String, ConnectionOfferError)] = [
            (Self.offerJSON(v: 1), .unsupportedVersion(1)),
            (Self.offerJSON(v: 3), .unsupportedVersion(3)),
            (Self.offerJSON(serverID: nil), .missingServerID),
            (Self.offerJSON(serverID: ""), .missingServerID),
            (Self.offerJSON(keyB64: nil), .invalidDaemonPublicKey),
            (Self.offerJSON(keyB64: ""), .invalidDaemonPublicKey),
            (Self.offerJSON(endpoint: nil), .malformedOffer),
            (Self.offerJSON(endpoint: "no-port"), .invalidRelayEndpoint),
            (Self.offerJSON(security: "legacy"), .unsupportedSecurityMode("legacy")),
        ]
        for (json, expected) in cases {
            #expect(throws: expected) {
                _ = try ConnectionOffer(link: Self.link(json: json))
            }
        }
    }

    @Test func aVersionThatIsNotANumberIsMalformed() {
        #expect(throws: ConnectionOfferError.malformedOffer) {
            _ = try ConnectionOffer(link: Self.link(json: Self.offerJSON().replacingOccurrences(
                of: "\"v\":2", with: "\"v\":\"2\"")))
        }
    }

    @Test func aSecurityPinThatIsNotAStringIsMalformed() {
        let json = Self.offerJSON(security: "protected").replacingOccurrences(
            of: "\"minimumSecurityMode\":\"protected\"", with: "\"minimumSecurityMode\":1")
        #expect(throws: ConnectionOfferError.malformedOffer) {
            _ = try ConnectionOffer(link: Self.link(json: json))
        }
    }

    // MARK: Key strictness

    @Test func theDaemonKeyMustBeCanonicalStandardBase64Of32Bytes() {
        // Wrong length for both directions.
        #expect(throws: ConnectionOfferError.invalidDaemonPublicKey) {
            _ = try ConnectionOffer.decodePublicKey("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHg==")
        }
        #expect(throws: ConnectionOfferError.invalidDaemonPublicKey) {
            _ = try ConnectionOffer.decodePublicKey("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISI=")
        }
        // URL-safe alphabet is not accepted for the key.
        #expect(throws: ConnectionOfferError.invalidBase64) {
            _ = try ConnectionOffer.decodePublicKey(
                String(Self.keyB64.dropLast(2)) + "8-")
        }
        // Unpadded.
        #expect(throws: ConnectionOfferError.invalidBase64) {
            _ = try ConnectionOffer.decodePublicKey(String(Self.keyB64.dropLast()))
        }
        // Padding in the middle.
        #expect(throws: ConnectionOfferError.invalidBase64) {
            _ = try ConnectionOffer.decodePublicKey("AA=A" + String(Self.keyB64.dropFirst(4)))
        }
        // Non-canonical trailing bits: `8` carries the two data bits and four zero bits, `9`
        // decodes to the same 32 bytes but is not what the daemon would emit.
        #expect(throws: ConnectionOfferError.invalidBase64) {
            _ = try ConnectionOffer.decodePublicKey(String(Self.keyB64.dropLast(2)) + "9=")
        }
    }

    @Test func aKeyThatIsNotCanonicalIsRefusedEndToEnd() {
        let json = Self.offerJSON(keyB64: String(Self.keyB64.dropLast(2)) + "9=")
        #expect(throws: ConnectionOfferError.invalidBase64) {
            _ = try ConnectionOffer(link: Self.link(json: json))
        }
    }

    // MARK: relay:// URIs

    @Test func aRelayURIProvidesEverythingTheOfferDoes() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://relay.example.test:443/\(Self.serverID)"
                + "?key=\(Self.keyB64)&ssl=true&security=protected&password=hunter2")
        #expect(offer.serverID == Self.serverID)
        #expect(offer.relayEndpoint == "relay.example.test:443")
        #expect(offer.relayUseTLS)
        #expect(offer.requiresProtectedSecurity)
        #expect(offer.password == "hunter2")
        #expect(offer.daemonPublicKey == Array(0..<32).map { UInt8($0) })
    }

    @Test func aRelayURIWithoutTheOptionalParametersIsAccepted() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://a.test:8443/\(Self.serverID)?key=\(Self.keyB64)")
        #expect(offer.relayUseTLS == false)
        #expect(offer.requiresProtectedSecurity == false)
        #expect(offer.password == nil)
    }

    @Test func anEmptyPasswordIsDropped() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://a.test:443/\(Self.serverID)?key=\(Self.keyB64)&password=")
        #expect(offer.password == nil)
    }

    @Test func relayURIQueryValuesArePercentDecoded() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://a.test:443/\(Self.serverID)?key=\(Self.keyB64)&password=a%2Fb%2Bc")
        #expect(offer.password == "a/b+c")
        // A literal plus in a query value means space, as URLSearchParams does it.
        let spaced = try ConnectionOffer(
            relayURI: "relay://a.test:443/\(Self.serverID)?key=\(Self.keyB64)&password=a+b")
        #expect(spaced.password == "a b")
    }

    @Test func aPercentEncodedServerIDIsDecoded() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://a.test:443/srv%5FAAAAAAAAAAAA?key=\(Self.keyB64)")
        #expect(offer.serverID == Self.serverID)
    }

    @Test func theConnectFragmentFormIsAccepted() throws {
        let uri = "relay://a.test:443/\(Self.serverID)?key=\(Self.keyB64)&ssl=true"
        let encoded = uri.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        let offer = try ConnectionOffer(link: "https://app.example.test/#connect=\(encoded ?? "")")
        #expect(offer.serverID == Self.serverID)
        #expect(offer.relayUseTLS)
    }

    @Test func aRelayURIWithAMissingPortIsRefused() {
        for uri in [
            "relay://a.test/\(Self.serverID)?key=\(Self.keyB64)",
            "relay://a.test:0/\(Self.serverID)?key=\(Self.keyB64)",
            "relay://a.test:65536/\(Self.serverID)?key=\(Self.keyB64)",
            "relay://a.test:port/\(Self.serverID)?key=\(Self.keyB64)",
        ] {
            #expect(throws: ConnectionOfferError.invalidRelayEndpoint) {
                _ = try ConnectionOffer(relayURI: uri)
            }
        }
    }

    @Test func aRelayURIWithoutServerIDOrKeyIsRefused() {
        #expect(throws: ConnectionOfferError.missingServerID) {
            _ = try ConnectionOffer(relayURI: "relay://a.test:443/?key=\(Self.keyB64)")
        }
        #expect(throws: ConnectionOfferError.invalidDaemonPublicKey) {
            _ = try ConnectionOffer(relayURI: "relay://a.test:443/\(Self.serverID)")
        }
        #expect(throws: ConnectionOfferError.invalidDaemonPublicKey) {
            _ = try ConnectionOffer(relayURI: "relay://a.test:443/\(Self.serverID)?key=")
        }
    }

    @Test func aServerIDContainingASlashIsRefused() {
        #expect(throws: ConnectionOfferError.invalidServerID) {
            _ = try ConnectionOffer(relayURI: "relay://a.test:443/a%2Fb?key=\(Self.keyB64)")
        }
    }

    @Test func anUnsupportedSecurityModeInTheURIIsRefused() {
        #expect(throws: ConnectionOfferError.unsupportedSecurityMode("legacy")) {
            _ = try ConnectionOffer(
                relayURI: "relay://a.test:443/\(Self.serverID)?key=\(Self.keyB64)&security=legacy")
        }
    }

    @Test func userinfoInTheRelayURIIsRefused() {
        #expect(throws: ConnectionOfferError.unsupportedRelayURI) {
            _ = try ConnectionOffer(
                relayURI: "relay://user:pass@a.test:443/\(Self.serverID)?key=\(Self.keyB64)")
        }
    }

    @Test func aURIThatIsNotRelaySchemeIsRefused() {
        for uri in ["tcp://a.test:6767/\(Self.serverID)?key=\(Self.keyB64)", "relay:a.test:443/x", "nonsense"] {
            #expect(throws: ConnectionOfferError.unsupportedRelayURI) {
                _ = try ConnectionOffer(relayURI: uri)
            }
        }
    }

    // MARK: Endpoint grammar

    @Test func theEndpointGrammarIsHostAndPort() throws {
        #expect(try ConnectionOffer.normalizeEndpoint(" localhost:6767 ") == "localhost:6767")
        #expect(try ConnectionOffer.normalizeEndpoint("my-relay.example.test:80")
            == "my-relay.example.test:80")
        #expect(try ConnectionOffer.normalizeEndpoint("host_with_underscore:1")
            == "host_with_underscore:1")
        #expect(try ConnectionOffer.normalizeEndpoint("[::1]:6767") == "[::1]:6767")

        for bad in [
            "", "host", "host:", ":80", "host:-1", "host:1.5", "host: 80", "h st:80",
            "-host:80", ".host:80", "host:123456", "host:80:90", "[::1]", "[::1]80",
            "[zzzz]:80", "[::1]:", "ho/st:80", "host:80/path",
        ] {
            #expect(throws: ConnectionOfferError.invalidRelayEndpoint) {
                _ = try ConnectionOffer.normalizeEndpoint(bad)
            }
        }
    }

    @Test func portExtractionMatchesTheNormalizedEndpoint() throws {
        #expect(ConnectionOffer.port(of: "a.test:443") == 443)
        #expect(ConnectionOffer.port(of: "[::1]:6767") == 6767)
        #expect(ConnectionOffer.port(of: "a.test") == nil)
        #expect(ConnectionOffer.port(of: "a.test:x") == nil)
    }

    // MARK: WebSocket URL

    @Test func theWebSocketURLCarriesTheRelayProtocolVersion() throws {
        let offer = try ConnectionOffer(
            link: Self.link(json: Self.offerJSON(endpoint: "a.test:443", useTLS: false)))
        #expect(try offer.relayWebSocketURL().absoluteString
            == "ws://a.test:443/ws?serverId=\(Self.serverID)&role=client&v=2")
    }

    @Test func theServerIDIsPercentEncodedIntoTheURL() throws {
        let offer = try ConnectionOffer(
            relayURI: "relay://a.test:443/srv%20x?key=\(Self.keyB64)")
        #expect(try offer.relayWebSocketURL().absoluteString
            == "ws://a.test:443/ws?serverId=srv%20x&role=client&v=2")
    }

    // MARK: base64url helper

    @Test func base64URLDecodingRejectsBrokenLength() {
        #expect(ConnectionOffer.decodeBase64URL("A") == nil)
        #expect(ConnectionOffer.decodeBase64URL("AAAA")?.count == 3)
        #expect(ConnectionOffer.decodeBase64URL("-_-_")?.count == 3)
        #expect(ConnectionOffer.decodeBase64URL("")?.isEmpty == true)
    }
}
