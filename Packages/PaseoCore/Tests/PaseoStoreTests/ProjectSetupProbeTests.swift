import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M2.13: the sidebar callout's config probe. Each case builds the read response inline;
/// the fixture capture `project_config_read_response` (missing paseo.json) is used where handy.
@Suite @MainActor
struct ProjectSetupProbeTests {
    private nonisolated static func readResponse(
        ok: Bool = true, config: String?
    ) throws -> ReadProjectConfigRequest.Response {
        let configJSON = config ?? "null"
        let json = Data("""
        {"type":"session","message":{"type":"read_project_config_response","payload":{
         "requestId":"probe-1","repoRoot":"/tmp/fixture-sandbox","ok":\(ok),
         "config":\(configJSON),"revision":null}}}
        """.utf8)
        return try JSONDecoder().decode(
            SessionPayloadEnvelope<ReadProjectConfigRequest.Response>.self, from: json
        ).payload
    }

    private func probe(client: FakeDaemonClient) -> ProjectSetupProbe {
        ProjectSetupProbe(client: client)
    }

    @Test func setupCommandsArrayMeansHasSetup() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: """
            {"worktree":{"setup":["npm ci","echo ready"]}}
            """)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == true)
    }

    @Test func setupCommandStringMeansHasSetup() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: #"{"worktree":{"setup":"npm ci"}}"#)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == true)
    }

    @Test func missingSetupCommandsMeansNoSetup() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: #"{"scripts":{"test":{"command":"npm test"}}}"#)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == false)
    }

    @Test func noPaseoJsonMeansNoSetup() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: nil)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == false)
    }

    @Test func teardownOnlyMeansNoSetup() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: #"{"worktree":{"teardown":["npm run clean"]}}"#)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == false)
    }

    @Test func failedReadIsCachedAndNotShown() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(ok: false, config: nil)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")
        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == nil)
        #expect(probe.failed.contains("/tmp/fixture-sandbox"))

        // A second check must not issue another read.
        await probe.check(repoRoot: "/tmp/fixture-sandbox")
        #expect(client.requests(ReadProjectConfigRequest.self).count == 1)
    }

    @Test func sendFailureIsCachedAndNotShown() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("offline")
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == nil)
        #expect(probe.failed.contains("/tmp/fixture-sandbox"))
    }

    @Test func resultIsCachedAfterOneRead() async throws {
        let client = FakeDaemonClient()
        client.on(ReadProjectConfigRequest.self) { _ in
            try Self.readResponse(config: #"{"worktree":{"setup":["make build"]}}"#)
        }
        let probe = probe(client: client)

        await probe.check(repoRoot: "/tmp/fixture-sandbox")
        await probe.check(repoRoot: "/tmp/fixture-sandbox")

        #expect(client.requests(ReadProjectConfigRequest.self).count == 1)
        #expect(probe.hasSetupCommands["/tmp/fixture-sandbox"] == true)
    }
}
