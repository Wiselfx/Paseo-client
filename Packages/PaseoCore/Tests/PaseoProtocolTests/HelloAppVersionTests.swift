import Foundation
import PaseoProtocol
import Testing

/// Regression for the M2.5a "pi and omp are missing" bug.
///
/// The daemon only advertises providers outside `claude`/`codex`/`opencode` to clients whose
/// hello says app version 0.1.45 or newer (`MIN_VERSION_ALL_PROVIDERS` upstream). The app's
/// bundle version can be lower than that protocol floor, so the hello must never claim less than
/// the behavior this client implements.
@Suite
struct HelloAppVersionTests {
    private func encoded(_ appVersion: String?) throws -> [String: Any] {
        let hello = Hello(
            clientId: "test-client", appVersion: appVersion, credential: .password("secret"))
        let data = try JSONEncoder().encode(hello)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anEarlyBundleVersionIsRaisedToTheProviderGate() throws {
        let hello = try encoded("0.1.0")
        #expect(hello["appVersion"] as? String == "0.1.45")
    }

    @Test func theGateItselfPassesThrough() throws {
        #expect(try encoded("0.1.45")["appVersion"] as? String == "0.1.45")
    }

    @Test func newerVersionsPassThroughUnchanged() throws {
        #expect(try encoded("1.2.3")["appVersion"] as? String == "1.2.3")
        #expect(try encoded("0.2.0-beta.1")["appVersion"] as? String == "0.2.0-beta.1")
    }

    @Test func aMissingVersionStillIdentifiesAsProviderAware() throws {
        #expect(try encoded(nil)["appVersion"] as? String == "0.1.45")
    }

    @Test func theFloorMatchesTheDaemonsAllProvidersVersion() {
        #expect(paseoProviderAwareAppVersion == "0.1.45")
    }
}
