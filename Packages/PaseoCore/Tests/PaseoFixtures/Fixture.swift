import Foundation

/// Real daemon traffic captured with `Tools/capture-fixtures.mjs` from a throwaway agent in
/// /tmp/fixture-sandbox, then scrubbed of private ids. Regenerate when the daemon changes;
/// never hand-edit a fixture to make a test pass.
///
/// The turn in `stream/` is the same turn that appears, projected, at the end of
/// `fetch_agent_timeline_response`. Replaying the stream must reproduce those projected rows.
public enum Fixture {
    public static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// A fixture inside one area directory, e.g. `Fixtures/workspaces/checkout_status_response.json`.
    public static func data(_ name: String, in area: String) throws -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures/" + area)
        else {
            throw FixtureError.missing("\(area)/\(name)")
        }
        return try Data(contentsOf: url)
    }

    /// Every `agent_stream` frame of one turn, in arrival order.
    public static func streamFrames() throws -> [Data] {
        guard let dir = Bundle.module.url(forResource: "stream", withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing("stream")
        }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try Data(contentsOf: $0) }
    }

    public enum FixtureError: Error { case missing(String) }
}
