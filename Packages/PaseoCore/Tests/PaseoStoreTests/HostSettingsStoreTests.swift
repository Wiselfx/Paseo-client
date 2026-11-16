import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Drives `HostSettingsStore` with the traffic captured by `Tools/capture-host-settings.mjs`.
@Suite @MainActor
struct HostSettingsStoreTests {
    private enum Fixtures {
        static let decoder = JSONDecoder()

        static func payload<T: Decodable & Sendable>(_ name: String, as type: T.Type) throws -> T {
            try decoder.decode(
                SessionPayloadEnvelope<T>.self, from: Fixture.hostSettings(name)
            ).payload
        }

        static func serverInfo() throws -> ServerInfo {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ServerInfo>.self,
                from: Fixture.hostSettings("server_info")
            ).payload
        }

        static func configResponse() throws -> GetDaemonConfigRequest.Response {
            try payload("get_daemon_config_response", as: GetDaemonConfigRequest.Response.self)
        }

        static func patchResponse() throws -> SetDaemonConfigRequest.Response {
            try payload("set_daemon_config_response", as: SetDaemonConfigRequest.Response.self)
        }

        static func commandsResponse() throws -> ListCommandsRequest.Response {
            try payload("list_commands_response", as: ListCommandsRequest.Response.self)
        }

        static func pushUnregisterResponse() throws -> PushUnregisterRequest.Response {
            try payload("push_unregister_response", as: PushUnregisterRequest.Response.self)
        }
    }

    @Test func loadReadsTheConfigAndCapabilities() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        store.serverInfoChanged(try Fixtures.serverInfo())
        let response = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in response }

        await store.load()

        #expect(store.phase == .ready)
        #expect(store.error == nil)
        #expect(store.config?.mcp?.injectIntoAgents == true)
        #expect(store.config?.providers.count == 8)
        #expect(store.isProviderEnabled("opencode"))
        #expect(!store.isProviderEnabled("copilot"))
        #expect(store.isProviderEnabled("provider-with-no-config-row"))
        #expect(store.providerSettings.count == 8)
        #expect(store.supportsProfiles)
        #expect(store.supportsPushTokenRevocation)
        #expect(store.profiles.isEmpty, "the captured config has no saved profiles")
    }

    @Test func profilesAreGatedOnTheDaemonFeatureFlag() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var info = try Fixtures.serverInfo()
        info.features = ["agentProfiles": .bool(true)]
        store.serverInfoChanged(info)

        var response = try Fixtures.configResponse()
        response.config.agentProfiles = [
            AgentProfile(id: "p1", name: "Fast", provider: "pi", model: "m", notes: "for small jobs")
        ]
        let served = response
        client.onSend(GetDaemonConfigRequest.self) { _ in served }
        await store.load()
        #expect(store.profiles.map(\.id) == ["p1"])

        info.features = ["agentProfiles": .bool(false)]
        store.serverInfoChanged(info)
        #expect(store.profiles.isEmpty, "an old daemon would drop the key on save")
    }

    @Test func saveSendsOnlyThePatchAndAppliesTheEffectiveConfig() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var response = try Fixtures.patchResponse()
        response.config.providers["copilot"]?.enabled = false
        let served = response
        client.onSend(SetDaemonConfigRequest.self) { _ in served }

        var patch = DaemonConfigPatch()
        patch.resumePrompt = "Resume now."
        let saved = await store.save(patch)

        #expect(saved)
        #expect(store.error == nil)
        #expect(store.phase == .ready)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        #expect(sent.config.resumePrompt == "Resume now.")
        #expect(sent.config.autoArchiveAfterMerge == nil, "unset fields stay out of the frame")
        #expect(store.config?.resumePrompt == "Resume working. [fixture-capture]")
    }

    @Test func aFailedSaveReportsTheErrorAndKeepsTheOldConfig() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        let response = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in response }
        await store.load()
        let previousPrompt = store.config?.resumePrompt

        var patch = DaemonConfigPatch()
        patch.appendSystemPrompt = "nope"
        let saved = await store.save(patch)

        #expect(!saved)
        #expect(store.error != nil)
        #expect(store.config?.resumePrompt == previousPrompt)
        #expect(store.phase == .ready, "a failed write must not blow away the loaded config")
    }

    @Test func setProviderEnabledWritesAProviderPatch() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        let loaded = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in loaded }
        await store.load()

        var response = try Fixtures.patchResponse()
        response.config.providers["copilot"]?.enabled = true
        let served = response
        client.onSend(SetDaemonConfigRequest.self) { _ in served }

        let saved = await store.setProviderEnabled("copilot", true)

        #expect(saved)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        #expect(sent.config.providers?["copilot"]?.enabled == true)
        #expect(sent.config.providers?.count == 1, "providers is a merge, not a replacement")
        #expect(sent.config.resumePrompt == nil)
        #expect(store.isProviderEnabled("copilot"))
    }

    @Test func commandsLoadForTheLiveAgentAndDrafts() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        let response = try Fixtures.commandsResponse()
        client.onSend(ListCommandsRequest.self) { _ in response }

        let commands = await store.loadCommands(for: "agent-1")

        #expect(commands.count == 25)
        #expect(store.commands(for: "agent-1").count == 25)
        #expect(store.commandError(for: "agent-1") == nil)
        let sent = try #require(client.requests(ListCommandsRequest.self).first)
        #expect(sent.agentId == "agent-1")
        #expect(sent.draftConfig == nil)

        let draft = AgentDraftConfig(provider: "pi", cwd: "/tmp/fixture-sandbox", model: "m")
        _ = await store.loadCommands(for: "agent-2", draft: draft)
        let draftRequest = try #require(client.requests(ListCommandsRequest.self).last)
        #expect(draftRequest.agentId == "agent-2")
        #expect(draftRequest.draftConfig?.provider == "pi")
        #expect(draftRequest.draftConfig?.cwd == "/tmp/fixture-sandbox")

        store.clearCommands(for: "agent-1")
        #expect(store.commands(for: "agent-1").isEmpty)
    }

    @Test func commandErrorsArePerAgentAndKeepTheLastMenu() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        let initial = try Fixtures.commandsResponse()
        client.onSend(ListCommandsRequest.self) { _ in initial }
        _ = await store.loadCommands(for: "agent-1")
        #expect(store.commands(for: "agent-1").count == 25)

        var response = initial
        response.error = "provider is still warming up"
        let failing = response
        client.onSend(ListCommandsRequest.self) { _ in failing }
        let returned = await store.loadCommands(for: "agent-1")

        #expect(returned.count == 25, "a failed refresh keeps the previous menu")
        #expect(store.commandError(for: "agent-1") == "provider is still warming up")
        #expect(store.commandError(for: "agent-2") == nil)
    }

    @Test func presenceSendsOnStartChangesAndTheInterval() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client, heartbeatInterval: .milliseconds(25))

        store.startPresence(deviceType: .mobile, focusedAgentId: "agent-a", appVisible: true)
        let started = await eventually { heartbeats(client).count >= 1 }
        #expect(started)
        let first = try #require(heartbeats(client).first)
        #expect(first.deviceType == .mobile)
        #expect(first.focusedAgentId == "agent-a")
        #expect(first.appVisible)
        #expect(first.appVisibilityChangedAt == nil)
        #expect(store.isPresenting)
        #expect(store.lastPresenceSentAt != nil)

        let periodic = await eventually { heartbeats(client).count >= 3 }
        #expect(periodic, "the heartbeat must repeat on its own")

        store.stopPresence()
        try await Task.sleep(for: .milliseconds(80))
        let afterStop = heartbeats(client).count
        try await Task.sleep(for: .milliseconds(100))
        #expect(heartbeats(client).count == afterStop)
        #expect(!store.isPresenting)
    }

    @Test func presenceChangesSendImmediately() async throws {
        let client = FakeDaemonClient()
        // Long interval: only explicit changes can add heartbeats during this test.
        let store = HostSettingsStore(client: client, heartbeatInterval: .seconds(30))
        store.startPresence(deviceType: .web, focusedAgentId: "agent-a", appVisible: true)

        let started = await eventually { heartbeats(client).count == 1 }
        #expect(started)
        #expect(heartbeats(client).first?.deviceType == .web)

        store.updateVisibility(false)
        let hiddenSent = await eventually { heartbeats(client).count == 2 }
        #expect(hiddenSent)
        let hidden = try #require(heartbeats(client).last)
        #expect(!hidden.appVisible)
        #expect(hidden.appVisibilityChangedAt != nil)
        #expect(!(hidden.appVisibilityChangedAt ?? "").isEmpty)

        store.updateFocus("agent-b")
        let focusSent = await eventually { heartbeats(client).count == 3 }
        #expect(focusSent)
        #expect(heartbeats(client).last?.focusedAgentId == "agent-b")

        store.updateVisibility(false)
        try await Task.sleep(for: .milliseconds(50))
        #expect(heartbeats(client).count == 3, "an unchanged visibility sends nothing")
        store.stopPresence()
    }

    @Test func pushRegistrationAndRevocationFollowTheCapabilityFlag() async throws {
        let client = FakeDaemonClient()
        let store = HostSettingsStore(client: client)
        var info = try Fixtures.serverInfo()
        info.features = ["pushTokenRevocation": .bool(false)]
        store.serverInfoChanged(info)

        await store.registerPushToken("  token-1  ")
        let registered = await eventually { registeredTokens(client) == ["token-1"] }
        #expect(registered)
        #expect(store.error == nil)

        let revoked = await store.unregisterPushToken("token-1")
        #expect(!revoked)
        #expect(store.error == "This host cannot revoke push tokens.")
        #expect(client.requests(PushUnregisterRequest.self).isEmpty)

        info.features = ["pushTokenRevocation": .bool(true)]
        store.serverInfoChanged(info)
        client.onSend(PushUnregisterRequest.self) { _ in try Fixtures.pushUnregisterResponse() }
        let revokedNow = await store.unregisterPushToken(" token-1 ")
        #expect(revokedNow)
        #expect(store.error == nil)
        #expect(client.requests(PushUnregisterRequest.self).first?.token == "token-1")
    }

    @Test func daemonConfigChangedStatusReachesTheSessionStore() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        let info = try Fixtures.serverInfo()
        client.push(.connected(info))
        let session = HostSession(client: client)
        await session.start()
        _ = await eventually { session.connection == .connected(info) }
        #expect(session.hostSettings.supportsProfiles)

        client.push(
            .unhandled(
                messageType: "status",
                raw: try Fixture.hostSettings("daemon_config_changed")))
        let updated = await eventually {
            session.hostSettings.config?.resumePrompt == "Resume working. [fixture-capture]"
        }
        #expect(updated)
        #expect(session.hostSettings.phase == .ready)
    }

    // MARK: Helpers

    private func heartbeats(_ client: FakeDaemonClient) -> [ClientHeartbeat] {
        client.messages.compactMap { $0 as? ClientHeartbeat }
    }

    private func registeredTokens(_ client: FakeDaemonClient) -> [String] {
        client.messages.compactMap { ($0 as? RegisterPushToken)?.token }
    }
}
