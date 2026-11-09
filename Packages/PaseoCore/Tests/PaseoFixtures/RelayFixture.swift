import Foundation

/// Relay vectors for R16, copied verbatim from the public `rweather/noise-c` "cacophony" suite the
/// daemon's own relay package tests against (`packages/relay/src/noise/fixtures/`).
///
/// Third-party test data, not captured traffic: no host, keypair or offer material is in here, and
/// it must not be edited. The `handshake_hash` field is optional per vector.
extension Fixture {
    public static func relay(_ name: String) throws -> Data {
        try data(name, in: "relay")
    }
}
