import Foundation

/// Fixtures captured for the host-settings area (T10), from the live daemon's read-only RPCs and
/// one temporarily patched `resumePrompt` that was restored immediately.
extension Fixture {
    public static func hostSettings(_ name: String) throws -> Data {
        try data(name, area: "host-settings")
    }
}
