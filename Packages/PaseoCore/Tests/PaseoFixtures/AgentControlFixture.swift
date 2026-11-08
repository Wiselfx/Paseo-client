import Foundation

/// Fixtures captured for the agent-control area (T6), from sandbox agents in /tmp/fixture-sandbox.
extension Fixture {
    /// Loads `<area>/<name>.json`, e.g. `agentControl("permission_request_question")`.
    public static func data(_ name: String, area: String) throws -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures/\(area)")
        else {
            throw FixtureError.missing("\(area)/\(name)")
        }
        return try Data(contentsOf: url)
    }

    /// The agent-control capture area, as recorded by `Tools/capture-agent-control.mjs`.
    public static func agentControl(_ name: String) throws -> Data {
        try data(name, area: "agent-control")
    }
}
