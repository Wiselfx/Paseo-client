import Foundation

/// Synthetic fixtures for forge search: invented numbers/titles, `example.invalid` urls.
extension Fixture {
    public static func forgeSearch(_ name: String) throws -> Data {
        try data(name, area: "forge-search")
    }
}
