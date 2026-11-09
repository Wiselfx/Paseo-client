import Foundation

// The daemon's pairing offer ("Host settings → Pair device"): the phone-side fetch of the
// same JSON the daemon renders as a QR/URL in Paseo Desktop.
// Source: messages.ts `DaemonGetPairingOfferRequestSchema` (:1489),
// `DaemonGetPairingOfferResponseSchema` (:5439-5448).
// Gated on `features.daemonStatusRpc` (:3866); relay enablement additionally needs
// `features.relayConfig` (:3872) and is a `set_daemon_config_request` patch
// (`MutableDaemonConfigPatchSchema` `relay`).
//
// The response carries the offer URL — a credential (whoever holds it can reach a daemon
// with no password set). Never log it, persist it, or put it in error strings. The store
// keeps it transient and the page clears it on close.

/// Fetches the pairing offer (URL + relay state). No parameters on the wire.
public struct DaemonGetPairingOfferRequest: PaseoRequest {
    public static let type = "daemon.get_pairing_offer.request"
    public static let responseType = "daemon.get_pairing_offer.response"
    public var requestId = ""
    public init() {}

    // Source: messages.ts `DaemonGetPairingOfferResponseSchema`
    public struct Response: Decodable, Sendable {
        public var requestId: String
        /// Zero or more offers: exactly one today. The schema types `url` as a non-null
        /// string, but a relay-disabled daemon answers `{relayEnabled:false, url:null}`
        /// (docs/research/11-relay-pairing.md §7), so decode tolerantly and treat nil as
        /// "no link", never as a decode failure.
        public var url: String?
        /// The daemon's terminal QR block (`\u001b` colours); the app ignores it and
        /// re-renders the URL itself.
        public var qr: String?
        public var relayEnabled: Bool

        public init(requestId: String, url: String?, qr: String? = nil, relayEnabled: Bool) {
            self.requestId = requestId
            self.url = url
            self.qr = qr
            self.relayEnabled = relayEnabled
        }
    }
}
