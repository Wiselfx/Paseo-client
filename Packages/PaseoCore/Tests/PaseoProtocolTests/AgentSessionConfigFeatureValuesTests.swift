import Foundation
import PaseoProtocol
import Testing

@Suite
struct AgentSessionConfigFeatureValuesTests {
    @Test func encodesFeatureValuesWhenSet() throws {
        let config = AgentSessionConfig(
            provider: "claude", cwd: "/tmp/fixture-sandbox",
            featureValues: ["fast_mode": .bool(true)])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        let dict = try #require(object as? [String: Any])
        let values = try #require(dict["featureValues"] as? [String: Any])
        #expect(values["fast_mode"] as? Bool == true)
    }

    @Test func omitsFeatureValuesWhenNil() throws {
        let config = AgentSessionConfig(provider: "claude", cwd: "/tmp/fixture-sandbox")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        let dict = try #require(object as? [String: Any])
        #expect(dict["featureValues"] == nil)
    }
}
