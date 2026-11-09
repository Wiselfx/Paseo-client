import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// V4 §1: the host settings page's two daemon-wide cards — "Release idle agents"
/// (`idleRuntimeCleanup`, COMPAT v0.13.0) and "Resume agents after restart"
/// (`resumeOnStartup`/`resumePrompt`, COMPAT v0.14.0). Both are optional on the wire and gated on
/// a host feature flag, so a host that does not report them must keep the fields unset and the
/// cards hidden.
@Suite @MainActor
struct HostRestartSettingsTests {
    private enum Fixtures {
        static let decoder = JSONDecoder()

        static func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
            try decoder.decode(
                SessionPayloadEnvelope<T>.self, from: Fixture.hostSettings(name)
            ).payload
        }

        static func serverInfo() throws -> ServerInfo {
            try payload("server_info", as: ServerInfo.self)
        }

        static func configResponse() throws -> GetDaemonConfigRequest.Response {
            try payload("get_daemon_config_response", as: GetDaemonConfigRequest.Response.self)
        }

        static func patchResponse() throws -> SetDaemonConfigRequest.Response {
            try payload("set_daemon_config_response", as: SetDaemonConfigRequest.Response.self)
        }
    }

    /// The captured config: idle cleanup on, restart recovery off with a saved prompt.
    @Test func decodesTheIdleAndRestartSettings() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try Fixtures.serverInfo())
        let response = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in response }

        await store.load()

        #expect(store.config?.idleRuntimeCleanup == true)
        #expect(store.config?.resumeOnStartup == false)
        #expect(store.config?.resumePrompt == "Resume working.")
    }

    /// Both cards are COMPAT-gated: an older host does not report the feature, so the settings
    /// page must not offer a toggle whose patch that host would drop.
    @Test func theCardsAreGatedOnTheHostFeatures() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        let response = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in response }

        store.serverInfoChanged(try Fixtures.serverInfo())
        #expect(store.supportsIdleRuntimeCleanup)
        #expect(store.supportsResumeOnStartup)

        var old = try Fixtures.serverInfo()
        old.features = ["agentProfiles": .bool(true)]
        store.serverInfoChanged(old)
        #expect(!store.supportsIdleRuntimeCleanup)
        #expect(!store.supportsResumeOnStartup)

        var noFeatures = try Fixtures.serverInfo()
        noFeatures.features = nil
        store.serverInfoChanged(noFeatures)
        #expect(!store.supportsIdleRuntimeCleanup)
        #expect(!store.supportsResumeOnStartup)
    }

    /// An old daemon's config omits both keys, and the read model must not invent a value: the
    /// idle switch shows its default (on) and the resume switch its default (off).
    @Test func aConfigWithoutTheKeysLeavesThemUnset() throws {
        let config = try JSONDecoder().decode(DaemonConfig.self, from: Data("{}".utf8))
        #expect(config.idleRuntimeCleanup == nil)
        #expect(config.resumeOnStartup == nil)
        #expect(config.resumePrompt == nil)
    }

    @Test func theIdleCleanupPatchCarriesOnlyThatField() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var response = try Fixtures.patchResponse()
        response.config.idleRuntimeCleanup = false
        let served = response
        client.onSend(SetDaemonConfigRequest.self) { _ in served }

        var patch = DaemonConfigPatch()
        patch.idleRuntimeCleanup = false
        #expect(await store.save(patch))

        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        let json = try encodedJSON(sent.config)
        #expect(json["idleRuntimeCleanup"] as? Bool == false)
        #expect(json["resumeOnStartup"] == nil, "unset fields stay out of the frame")
        #expect(json["resumePrompt"] == nil)
        #expect(json["appendSystemPrompt"] == nil)
        #expect(store.config?.idleRuntimeCleanup == false)
    }

    @Test func theRestartRecoveryPatchesCarryTheirOwnFields() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var response = try Fixtures.patchResponse()
        response.config.resumeOnStartup = true
        response.config.resumePrompt = "Resume working."
        let served = response
        client.onSend(SetDaemonConfigRequest.self) { _ in served }

        var toggle = DaemonConfigPatch()
        toggle.resumeOnStartup = true
        #expect(await store.save(toggle))
        let toggled = try #require(client.requests(SetDaemonConfigRequest.self).first)
        let toggleJSON = try encodedJSON(toggled.config)
        #expect(toggleJSON["resumeOnStartup"] as? Bool == true)
        #expect(toggleJSON["resumePrompt"] == nil)
        #expect(toggleJSON["idleRuntimeCleanup"] == nil)

        var prompt = DaemonConfigPatch()
        prompt.resumePrompt = "Resume working."
        #expect(await store.save(prompt))
        let withPrompt = try #require(client.requests(SetDaemonConfigRequest.self).last)
        let promptJSON = try encodedJSON(withPrompt.config)
        #expect(promptJSON["resumePrompt"] as? String == "Resume working.")
        #expect(promptJSON["resumeOnStartup"] == nil)
        #expect(store.config?.resumePrompt == "Resume working.")
    }

    /// The wire shape the daemon's patch schema expects (messages.ts:240-271): a flat object of
    /// the fields being written, nothing else.
    private func encodedJSON(_ patch: DaemonConfigPatch) throws -> [String: Any] {
        let data = try JSONEncoder().encode(patch)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
