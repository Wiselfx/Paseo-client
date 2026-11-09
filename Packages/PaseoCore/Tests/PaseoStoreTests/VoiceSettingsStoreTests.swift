import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Drives `VoiceSettingsStore` (+ `HostSettingsStore` for the config document) with the
/// captured host-settings traffic and hand-built local-model list responses.
@Suite @MainActor
struct VoiceSettingsStoreTests {
    private enum Fixtures {
        static func serverInfo() throws -> ServerInfo {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<ServerInfo>.self,
                from: Fixture.hostSettings("server_info")
            ).payload
        }

        static func configResponse() throws -> GetDaemonConfigRequest.Response {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<GetDaemonConfigRequest.Response>.self,
                from: Fixture.hostSettings("get_daemon_config_response")
            ).payload
        }

        static func patchResponse() throws -> SetDaemonConfigRequest.Response {
            try JSONDecoder().decode(
                SessionPayloadEnvelope<SetDaemonConfigRequest.Response>.self,
                from: Fixture.hostSettings("set_daemon_config_response")
            ).payload
        }
    }

    private func makeStores(_ client: FakeDaemonClient) async throws -> (HostSettingsStore, VoiceSettingsStore) {
        let hostSettings = HostSettingsStore(client: client)
        let voice = VoiceSettingsStore(client: client, hostSettings: hostSettings)
        hostSettings.serverInfoChanged(try Fixtures.serverInfo())
        voice.serverInfoChanged(try Fixtures.serverInfo())
        let response = try Fixtures.configResponse()
        client.onSend(GetDaemonConfigRequest.self) { _ in response }
        await hostSettings.load()
        return (hostSettings, voice)
    }

    @Test func speechSettingsAreDecodedFromHostConfig() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)

        #expect(voice.supportsSpeechSettings, "the captured server_info advertises speechSettings")
        let speech = try #require(voice.speechSettings)
        #expect(speech.dictationEnabled == true)
        #expect(speech.dictationSTT.model == "parakeet-tdt-110m-en-int8")
        #expect(voice.site(.voiceModeTTS)?.model == "piper-en-us-libritts-r")
        #expect(voice.summary(for: .voiceModeTTS) == .local(modelLabel: "piper-en-us-libritts-r"))
    }

    @Test func gateIsOffWithoutTheFeatureFlag() async throws {
        let client = FakeDaemonClient()
        let hostSettings = HostSettingsStore(client: client)
        let voiceSettingsStore = VoiceSettingsStore(client: client, hostSettings: hostSettings)
        let info = try JSONDecoder().decode(
            ServerInfo.self, from: Data(#"{"serverId":"s","features":{}}"#.utf8))
        hostSettings.serverInfoChanged(info)
        voiceSettingsStore.serverInfoChanged(info)
        #expect(!voiceSettingsStore.supportsSpeechSettings)
    }

    @Test func dictationSwitchPatchesOnlyTheSwitch() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        let response = try Fixtures.patchResponse()
        client.onSend(SetDaemonConfigRequest.self) { _ in response }

        let saved = await voice.setDictationEnabled(false)

        #expect(saved)
        #expect(voice.error == nil)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).first)
        #expect(sent.config.features?["dictation"]?["enabled"] == .bool(false))
        #expect(sent.config.features?["voiceMode"] == nil)
        #expect(sent.config.resumePrompt == nil, "no other config field is rewritten")
    }

    @Test func siteSavePatchesTheSiteAndRefreshesModels() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        let response = try Fixtures.patchResponse()
        client.onSend(SetDaemonConfigRequest.self) { _ in response }
        client.onSend(SpeechLocalModelsListRequest.self) { _ in
            try! JSONDecoder().decode(
                SpeechLocalModelsListRequest.Response.self,
                from: Data(#"{"requestId":"r","error":null,"models":[]}"#.utf8))
        }
        await voice.loadModels()

        var site = SpeechSitePatch()
        site.provider = .openai
        site.apiKey = .some("test-key-value")
        site.model = .some("tts-1")
        site.voice = .some("nova")

        let saved = await voice.save(siteID: .voiceModeTTS, sitePatch: site)

        #expect(saved)
        let sent = try #require(client.requests(SetDaemonConfigRequest.self).last)
        let tts = sent.config.features?["voiceMode"]?["tts"]
        #expect(tts?["provider"] == .string("openai"))
        #expect(tts?["model"] == .string("tts-1"))
        #expect(tts?["voice"] == .string("nova"))
        #expect(tts?["apiKey"] == .string("test-key-value"))
        #expect(tts?["baseUrl"] == nil)
        #expect(sent.config.features?["dictation"] == nil)
        let listRequests = client.requests(SpeechLocalModelsListRequest.self).count
        #expect(listRequests == 2, "the save re-reads the catalog (model selection changes inUse)")
    }

    @Test func downloadAndDeleteSendRequestsAndRelist() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        client.onSend(SpeechLocalModelsListRequest.self) { _ in
            try! JSONDecoder().decode(
                SpeechLocalModelsListRequest.Response.self,
                from: Data(#"{"requestId":"r","error":null,"models":[]}"#.utf8))
        }
        client.onSend(SpeechLocalModelsDownloadRequest.self) { request in
            #expect(request.modelId == "whisper")
            return try! JSONDecoder().decode(
                SpeechLocalModelsDownloadRequest.Response.self,
                from: Data(#"{"requestId":"r","error":null}"#.utf8))
        }
        client.onSend(SpeechLocalModelsDeleteRequest.self) { request in
            #expect(request.modelId == "whisper")
            return try! JSONDecoder().decode(
                SpeechLocalModelsDeleteRequest.Response.self,
                from: Data(#"{"requestId":"r","error":null}"#.utf8))
        }

        let downloaded = await voice.download(modelId: "whisper")
        let deleted = await voice.delete(modelId: "whisper")

        #expect(downloaded)
        #expect(deleted)
        #expect(client.requests(SpeechLocalModelsDownloadRequest.self).count == 1)
        #expect(client.requests(SpeechLocalModelsDeleteRequest.self).count == 1)
        #expect(voice.modelActionErrors["whisper"] == nil)
    }

    @Test func failedModelActionsReportPerModel() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        client.onSend(SpeechLocalModelsDownloadRequest.self) { _ in
            try! JSONDecoder().decode(
                SpeechLocalModelsDownloadRequest.Response.self,
                from: Data(#"{"requestId":"r","error":"nope"}"#.utf8))
        }

        let downloaded = await voice.download(modelId: "whisper")

        #expect(!downloaded)
        #expect(voice.modelActionErrors["whisper"] == "nope")
    }

    @Test func pollingStartsWhileBusyAndStopsOnDemand() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        client.onSend(SpeechLocalModelsListRequest.self) { _ in
            try! JSONDecoder().decode(
                SpeechLocalModelsListRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","error":null,"models":[
                     {"id":"whisper","kind":"stt","label":"Whisper","description":"",
                      "languages":[],"downloadSizeBytes":100,"isDefault":false,"inUse":false,
                      "status":"downloading","receivedBytes":10,"totalBytes":100}]}
                    """#.utf8))
        }

        await voice.loadModels()
        #expect(voice.modelsPhase == .ready)
        #expect(voice.models.first?.status == .downloading)
        #expect(voice.isPollingModels)

        voice.stopModelPolling()
        #expect(!voice.isPollingModels)
    }

    @Test func modelKindFilter() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        client.onSend(SpeechLocalModelsListRequest.self) { _ in
            try! JSONDecoder().decode(
                SpeechLocalModelsListRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","error":null,"models":[
                     {"id":"s1","kind":"stt","label":"S","description":"","languages":[],
                      "downloadSizeBytes":1,"isDefault":false,"inUse":false,"status":"installed"},
                     {"id":"t1","kind":"tts","label":"T","description":"","languages":[],
                      "downloadSizeBytes":1,"isDefault":false,"inUse":false,"status":"installed"}]}
                    """#.utf8))
        }

        await voice.loadModels()
        #expect(voice.models(kind: .stt).map(\.id) == ["s1"])
        #expect(voice.models(kind: .tts).map(\.id) == ["t1"])
        voice.stopModelPolling()
    }

    @Test func offlineListLoadReportsFailure() async throws {
        let client = FakeDaemonClient()
        let (_, voice) = try await makeStores(client)
        await voice.loadModels()
        if case .failed = voice.modelsPhase {
            // no handler: the fake throws noHandler
        } else {
            Issue.record("expected a failed phase without a list handler")
        }
        #expect(voice.modelsError != nil)
    }
}
