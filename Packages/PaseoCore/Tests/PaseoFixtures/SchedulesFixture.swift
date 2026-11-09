import Foundation

/// Fixtures captured for the schedules area (T9), from sandbox schedules in /tmp/fixture-sandbox.
extension Fixture {
    /// The schedules capture area, as recorded by `Tools/capture-schedules.mjs`.
    public static func schedules(_ name: String) throws -> Data {
        try data(name, area: "schedules")
    }
}
