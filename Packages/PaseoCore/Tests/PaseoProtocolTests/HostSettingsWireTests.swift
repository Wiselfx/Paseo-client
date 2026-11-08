import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite
struct HostSettingsWireTests {
    @Test func decodesDaemonConfigFromCapturedTraffic() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<GetDaemonConfigRequest.Response>.self,
            from: Fixture.hostSettings("get_daemon_config_response")
        ).payload

        #expect(payload.requestId == "config")
        let config = payload.config
        #expect(config.mcp?.enabled == true)
        #expect(config.mcp?.injectIntoAgents == true)
        #expect(config.providers.count == 8)
        #expect(config.providers["opencode"]?.enabled == true)
        #expect(config.providers["copilot"]?.enabled == false)
        #expect(config.autoArchiveAfterMerge == false)
        #expect(config.enableTerminalAgentHooks == false)
        #expect(config.idleRuntimeCleanup == true)
        #expect(config.resumeOnStartup == false)
        #expect(config.resumePrompt == "Resume working.")
        #expect(config.appendSystemPrompt == "")
        #expect(config.browserTools?.enabled == false)
        #expect(config.usage?.enabled == true)
        #expect(config.envOverrides?.isEmpty == true)
        #expect(config.agentProfiles == nil)
    }

    @Test func decodesThePatchedConfigResponse() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<SetDaemonConfigRequest.Response>.self,
            from: Fixture.hostSettings("set_daemon_config_response")
        ).payload

        #expect(payload.config.resumePrompt == "Resume working. [fixture-capture]")
        #expect(payload.config.providers["pi"]?.enabled == true)
    }

    @Test func decodesTheDaemonConfigChangedStatus() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<DaemonConfigChanged>.self,
            from: Fixture.hostSettings("daemon_config_changed")
        ).payload

        #expect(payload.status == "daemon_config_changed")
        #expect(payload.config.resumePrompt == "Resume working. [fixture-capture]")
    }

    @Test func decodesSlashCommandsIncludingSkills() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<ListCommandsRequest.Response>.self,
            from: Fixture.hostSettings("list_commands_response")
        ).payload

        #expect(payload.agentId == "00000000-0000-4000-8000-000000000010")
        #expect(payload.error == nil)
        #expect(payload.commands.count == 25)
        let compact = try #require(payload.commands.first { $0.name == "compact" })
        #expect(compact.kind == .command)
        #expect(compact.argumentHint == "")
        let skill = try #require(payload.commands.first { $0.name == "opencode" })
        #expect(skill.kind == .skill)
        #expect(!skill.description.isEmpty)
    }

    @Test func decodesPushUnregisterResponse() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<PushUnregisterRequest.Response>.self,
            from: Fixture.hostSettings("push_unregister_response")
        ).payload

        #expect(payload.requestId == "push-unregister")
    }

    @Test func configToleratesUnknownKeysAndProviderFields() throws {
        let json = #"""
            {
              "mcp": {"enabled": true, "injectIntoAgents": false, "futureKnob": 3},
              "providers": {"pi": {"enabled": false, "env": {"X": "1"}, "future": true}},
              "autoArchiveAfterMerge": true,
              "appendSystemPrompt": "be brief",
              "agentProfiles": [
                {"id": "p1", "name": "Fast", "provider": "pi", "futureField": {"nested": true}}
              ],
              "brandNewDaemonSetting": {"whatever": [1, 2, 3]}
            }
            """#
        let config = try JSONDecoder().decode(DaemonConfig.self, from: Data(json.utf8))
        #expect(config.mcp?.enabled == true)
        #expect(config.mcp?.injectIntoAgents == false)
        #expect(config.providers["pi"]?.enabled == false)
        #expect(config.autoArchiveAfterMerge == true)
        #expect(config.appendSystemPrompt == "be brief")
        #expect(config.agentProfiles?.first?.id == "p1")
        #expect(config.agentProfiles?.first?.name == "Fast")
    }

    @Test func commandKindKeepsUnknownValues() throws {
        let json = #"""
            {"agentId":"a","commands":[{"name":"new-kind","description":"","argumentHint":"","kind":"widget"}],
             "error":null,"requestId":"r"}
            """#
        let response = try JSONDecoder().decode(
            ListCommandsRequest.Response.self, from: Data(json.utf8))
        #expect(response.commands.first?.kind == .unknown("widget"))
    }

    @Test func patchEncodesOnlyTheFieldsThatWereSet() throws {
        var patch = DaemonConfigPatch()
        patch.providers = ["copilot": DaemonConfigPatch.Provider(enabled: false)]
        patch.resumePrompt = "Resume now."

        let data = try JSONEncoder().encode(patch)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(value["resumePrompt"] == .string("Resume now."))
        #expect(value["providers"]?["copilot"]?["enabled"] == .bool(false))
        #expect(value["autoArchiveAfterMerge"] == nil)
        #expect(value["agentProfiles"] == nil)
    }

    @Test func heartbeatAlwaysEncodesTheNullableFocusKeys() throws {
        let heartbeat = ClientHeartbeat(
            deviceType: .mobile, focusedAgentId: nil, lastActivityAt: "2026-11-08T12:00:00.000Z",
            appVisible: false, appVisibilityChangedAt: "2026-11-08T11:59:00.000Z")
        let data = try JSONEncoder().encode(heartbeat)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(value["deviceType"] == .string("mobile"))
        #expect(value["focusedAgentId"] == .null)
        #expect(value["focusedTerminalId"] == .null)
        #expect(value["appVisible"] == .bool(false))
        #expect(value["appVisibilityChangedAt"] == .string("2026-11-08T11:59:00.000Z"))
    }

    @Test func listCommandsRequestEncodesTheDraftConfig() throws {
        let draft = AgentDraftConfig(
            provider: "pi", cwd: "/tmp/fixture-sandbox", modeId: "ask", model: "m",
            thinkingOptionId: "low", featureValues: ["fast": .bool(true)])
        let request = ListCommandsRequest(agentId: "a", draftConfig: draft)
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))

        #expect(value["agentId"] == .string("a"))
        #expect(value["draftConfig"]?["provider"] == .string("pi"))
        #expect(value["draftConfig"]?["cwd"] == .string("/tmp/fixture-sandbox"))
        #expect(value["draftConfig"]?["featureValues"]?["fast"] == .bool(true))
    }
}
