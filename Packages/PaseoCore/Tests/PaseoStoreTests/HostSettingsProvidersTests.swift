import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Additive `HostSettingsStore` coverage for the M4d provider/profile helpers: custom models,
/// profile persistence (daemon config write, gated on `features.agentProfiles`) and provider
/// diagnostics. Traffic is faked; no live daemon is contacted.
@Suite @MainActor
struct HostSettingsProvidersTests {
    private enum Fixtures {
        static let decoder = JSONDecoder()

        static func configResponse() throws -> GetDaemonConfigRequest.Response {
            try decoder.decode(
                SessionPayloadEnvelope<GetDaemonConfigRequest.Response>.self,
                from: Fixture.hostSettings("get_daemon_config_response")
            ).payload
        }

        static func patchResponse() throws -> SetDaemonConfigRequest.Response {
            try decoder.decode(
                SessionPayloadEnvelope<SetDaemonConfigRequest.Response>.self,
                from: Fixture.hostSettings("set_daemon_config_response")
            ).payload
        }

        static func serverInfo(agentProfiles: Bool) throws -> ServerInfo {
            var info = try decoder.decode(
                SessionPayloadEnvelope<ServerInfo>.self,
                from: Fixture.hostSettings("server_info")
            ).payload
            info.features = ["agentProfiles": .bool(agentProfiles)]
            return info
        }
    }

    @Test func additionalModelsDefaultToEmptyAndReflectTheConfig() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var response = try Fixtures.configResponse()
        response.config.providers["opencode"]?.additionalModels = [
            DaemonProviderModel(id: "z.ai/glm-4.7", label: "GLM-4.7"),
        ]
        let served = response
        client.onSend(GetDaemonConfigRequest.self) { _ in served }

        await store.load()

        #expect(store.additionalModels(for: "opencode").map(\.id) == ["z.ai/glm-4.7"])
        #expect(store.additionalModels(for: "claude").isEmpty)
        #expect(store.additionalModels(for: "provider-with-no-config-row").isEmpty)
    }

    @Test func saveProfilesSendsTheWholeListAndAdoptsTheEffectiveConfig() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try Fixtures.serverInfo(agentProfiles: true))
        let loaded = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in loaded }
        await store.load()

        var response = try Fixtures.patchResponse()
        response.config.agentProfiles = [
            AgentProfile(id: "p1", name: "Fast", provider: "pi", model: "m")
        ]
        let served = response
        client.onSend(SetDaemonConfigRequest.self) { _ in served }

        let next = [
            AgentProfile(id: "p2", name: "Deep", provider: "claude", model: "big"),
            AgentProfile(id: "p1", name: "Fast", provider: "pi"),
        ]
        let saved = await store.saveProfiles(next)

        #expect(saved)
        #expect(store.error == nil)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        #expect(sent.config.agentProfiles?.map(\.id) == ["p2", "p1"])
        #expect(sent.config.resumePrompt == nil, "profile writes must not smuggle other fields")
        #expect(store.profiles.map(\.id) == ["p1"], "effective config from the daemon is adopted")
    }

    @Test func saveProfilesIsGatedOnTheDaemonFeatureFlag() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try Fixtures.serverInfo(agentProfiles: false))
        let loaded = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in loaded }
        await store.load()

        let saved = await store.saveProfiles([
            AgentProfile(id: "p1", name: "Fast", provider: "pi")
        ])

        #expect(!saved)
        #expect(store.error != nil)
        #expect(client.requests(SetDaemonConfigRequest.self).isEmpty,
                "an old daemon would silently drop the key, so no write may be attempted")
    }

    @Test func providerDiagnosticStoresReadyText() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        client.onSend(ProviderDiagnosticRequest.self) { request in
            ProviderDiagnosticRequest.Response(
                requestId: request.requestId, provider: request.provider,
                diagnostic: "claude: ok\nversion 1.2.3")
        }

        let ok = await store.providerDiagnostic("claude")

        #expect(ok)
        #expect(store.providerDiagnostics["claude"] == .ready("claude: ok\nversion 1.2.3"))
        let sent = try #require(client.requests(ProviderDiagnosticRequest.self).first)
        #expect(sent.provider == "claude")
    }

    @Test func providerDiagnosticStoresFailureTextInsteadOfThrowing() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        client.onSend(ProviderDiagnosticRequest.self) { _ in
            throw FakeDaemonClient.FakeError.noHandler("provider_diagnostic_request")
        }

        let ok = await store.providerDiagnostic("codex")

        #expect(!ok)
        if case .failed(let message)? = store.providerDiagnostics["codex"] {
            #expect(!message.isEmpty)
        } else {
            Issue.record("expected .failed state, got \(String(describing: store.providerDiagnostics["codex"]))")
        }
    }
}
