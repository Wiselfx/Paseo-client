import Foundation

// Provider diagnostics.
// Source: messages.ts `ProviderDiagnosticRequestMessageSchema`,
// `ProviderDiagnosticResponseMessageSchema`
// (messages.ts:1911, messages.ts:6604).

// Source: messages.ts `ProviderDiagnosticRequestMessageSchema`

/// Asks the daemon to re-run its availability probe for one provider and return the raw log it
/// produced. Correlated by `requestId`; the app shows the text mono, copyable.
///
/// The probe can run a CLI or network check, so callers should allow a long timeout. No
/// capability flag gates this; daemons without diagnostics answer with an ordinary error, which
/// surfaces as the failure text.
public struct ProviderDiagnosticRequest: PaseoRequest {
    public static let type = "provider_diagnostic_request"
    public static let responseType = "provider_diagnostic_response"
    public var requestId = ""
    public var provider: String
    public init(provider: String) { self.provider = provider }

    // Source: messages.ts `ProviderDiagnosticResponseMessageSchema`
    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var provider: String
        public var diagnostic: String

        public init(requestId: String, provider: String, diagnostic: String) {
            self.requestId = requestId
            self.provider = provider
            self.diagnostic = diagnostic
        }
    }
}
