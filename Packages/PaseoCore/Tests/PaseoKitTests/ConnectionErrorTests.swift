import Foundation
import PaseoKit
import Testing

/// L3 Part C: connection errors a person can read, and which ones leave a mutation's outcome unknown
/// (public-docs/sdk/reference.md:259-262).
@Suite struct ConnectionErrorTests {
    static let every: [ConnectionError] = [
        .rejected(reason: "password_required"),
        .rejected(reason: "incorrect_password"),
        .rejected(reason: "incompatible_protocol"),
        .rejected(reason: "something_new"),
        .closed(code: 4002, reason: ""),
        .closed(code: 4003, reason: ""),
        .closed(code: 1006, reason: "abnormal"),
        .timeout,
        .transport("network is down"),
        .protocolViolation("could not decode fetch_agents_response"),
        .disconnected,
    ]

    /// Swift identifiers and enum-style spellings that must never reach the user.
    static let rawNames = [
        "protocolViolation", "ConnectionError", "rejected(", "closed(", "timeout(", "transport(",
        "disconnected", ".timeout", ".disconnected", ".rejected", ".closed", ".transport",
    ]

    @Test(arguments: every)
    func everyCaseHasAReadableSentence(_ error: ConnectionError) {
        let description = error.errorDescription ?? ""
        #expect(!description.isEmpty)
        for raw in Self.rawNames {
            #expect(!description.contains(raw), "\(description) leaks \(raw)")
        }
    }

    @Test func passwordAndWrongPasswordUseTheAppWording() {
        #expect(ConnectionError.rejected(reason: "password_required").errorDescription == "This host needs a password.")
        #expect(ConnectionError.rejected(reason: "incorrect_password").errorDescription == "Wrong password.")
    }

    @Test func outcomeIsUnknownOnlyWhenTheResponseMayHaveBeenLost() {
        #expect(ConnectionError.disconnected.outcomeUnknown)
        #expect(ConnectionError.timeout.outcomeUnknown)
        #expect(ConnectionError.closed(code: 1006, reason: "").outcomeUnknown)
        #expect(ConnectionError.transport("reset").outcomeUnknown)
        #expect(!ConnectionError.rejected(reason: "password_required").outcomeUnknown)
        #expect(!ConnectionError.protocolViolation("bad frame").outcomeUnknown)
    }

    @Test func aConnectionErrorIsALocalizedError() {
        let error: any Error = ConnectionError.timeout
        #expect((error as? LocalizedError)?.errorDescription == ConnectionError.timeout.errorDescription)
    }
}
