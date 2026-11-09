import Foundation

/// Synthetic fixtures for the import-session area: invented handle ids and titles, `/tmp`
/// paths only. No real session was imported to capture these.
extension Fixture {
    public static func importSession(_ name: String) throws -> Data {
        try data(name, area: "import-session")
    }
}
