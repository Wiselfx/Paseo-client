import Foundation

/// Fixtures captured for T12 (attachments, timeline search, provider subagents) by
/// `Tools/capture-attachments-search.mjs` from a throwaway agent in /tmp/fixture-sandbox.
extension Fixture {
    /// The T12 capture area, e.g. `attachmentsSearch("file_upload_response")`.
    public static func attachmentsSearch(_ name: String) throws -> Data {
        try data(name, area: "attachments-search")
    }
}
