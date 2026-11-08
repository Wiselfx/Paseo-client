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

    /// Every `agent_stream` frame of one turn, in arrival order.
    public static func streamFrames() throws -> [Data] {
        guard let dir = Bundle.module.url(forResource: "stream", withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing("stream")
        }
        return try jsonFiles(in: dir).map { try Data(contentsOf: $0) }
    }

    /// A captured terminal or script frame (`terminal` / `scripts`).
    public static func terminalData(_ name: String, scenario: String = "terminal") throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json",
            subdirectory: "Fixtures/terminals/\(scenario)"
        ) else { throw FixtureError.missing("terminals/\(scenario)/\(name)") }
        return try Data(contentsOf: url)
    }

    /// Captured binary terminal frames in arrival order. Payloads are base64 in the fixture.
    public static func terminalFrames(scenario: String = "terminal") throws -> [TerminalFrameFixture] {
        guard let dir = Bundle.module.url(
            forResource: "frames", withExtension: nil,
            subdirectory: "Fixtures/terminals/\(scenario)"
        ) else { throw FixtureError.missing("terminals/\(scenario)/frames") }
        return try jsonFiles(in: dir).map { url in
            try JSONDecoder().decode(TerminalFrameFixture.self, from: Data(contentsOf: url))
        }
    }

    private static func jsonFiles(in dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public struct TerminalFrameFixture: Decodable, Sendable {
        public var opcode: UInt8
        public var slot: UInt8
        public var payloadBase64: String
        public var payloadLength: Int?
        public var payloadText: String?

        public var payload: Data {
            Data(base64Encoded: payloadBase64) ?? Data()
        }

        /// Rebuilds the exact bytes the daemon sent, for the codec tests.
        public var encoded: Data {
            var data = Data([opcode, slot])
            data.append(payload)
            return data
        }
    }

    public enum FixtureError: Error { case missing(String) }
}
