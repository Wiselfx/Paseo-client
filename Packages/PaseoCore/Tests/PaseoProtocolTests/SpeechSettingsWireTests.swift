import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite
struct SpeechSettingsWireTests {
    @Test func decodesSpeechBlockFromCapturedDaemonConfig() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<GetDaemonConfigRequest.Response>.self,
            from: Fixture.hostSettings("get_daemon_config_response")
        ).payload

        let speech = try #require(SpeechSettings(features: payload.config.features))
        #expect(speech.dictationEnabled == true)
        #expect(speech.dictationSTT.provider == .local)
        #expect(speech.dictationSTT.model == "parakeet-tdt-110m-en-int8")
        #expect(speech.voiceModeEnabled == true)
        #expect(speech.voiceModeSTT.provider == .local)
        #expect(speech.voiceModeTTS.provider == .local)
        #expect(speech.voiceModeTTS.model == "piper-en-us-libritts-r")
        #expect(speech.site(.voiceModeTTS).model == "piper-en-us-libritts-r")
        #expect(speech.llmProvider == nil)
    }

    @Test func decodesOpenAISiteWithoutTheKeyItself() throws {
        let json = #"""
            {"dictation":{"enabled":true,"stt":{"provider":"openai","hasApiKey":true,
              "baseUrl":"https://example.invalid/v1","model":"whisper-1","language":"en",
              "confidenceThreshold":0.7,"unknownFuture":42}},
             "voiceMode":{"enabled":false,
              "stt":{"provider":"openai","hasApiKey":false,"model":"gpt-4o-transcribe"},
              "tts":{"provider":"openai","hasApiKey":true,"model":"tts-1","voice":"nova"}}}
            """#
        let speech = try JSONDecoder().decode(SpeechSettings.self, from: Data(json.utf8))

        let dictation = speech.dictationSTT
        #expect(dictation.provider == .openai)
        #expect(dictation.hasApiKey == true)
        #expect(dictation.baseUrl == "https://example.invalid/v1")
        #expect(dictation.model == "whisper-1")
        #expect(dictation.language == "en")
        #expect(dictation.confidenceThreshold == 0.7)
        let tts = speech.voiceModeTTS
        #expect(tts.provider == .openai)
        #expect(tts.voice == "nova")
        #expect(speech.voiceModeEnabled == false)
    }

    @Test func unknownProviderAndMissingBlocksStayDecodable() throws {
        let unknown = #"""
            {"dictation":{"enabled":true,"stt":{"provider":"whisper-server","model":"x"}},
             "voiceMode":{"enabled":true,"stt":{"provider":"local"},"tts":{"provider":"local"}}}
            """#
        let speech = try JSONDecoder().decode(SpeechSettings.self, from: Data(unknown.utf8))
        #expect(speech.dictationSTT.provider == .unknown("whisper-server"))
        #expect(speech.dictationSTT.model == "x")

        #expect(SpeechSettings(features: nil) == nil)
        #expect(SpeechSettings(features: .null) == nil)
        let notSpeech = JSONValue.object(["usage": .object(["enabled": .bool(true)])])
        #expect(SpeechSettings(features: notSpeech) == nil)
    }

    @Test func patchOnlyContainsTheSectionsThatChanged() throws {
        var site = SpeechSitePatch()
        site.provider = .openai
        site.apiKey = .some("test-key-value")
        site.baseUrl = .some(nil)
        site.model = .some("whisper-1")
        let patch = SpeechSettingsPatch(dictationEnabled: true, dictationSTT: site)

        let value = patch.jsonValue
        #expect(value["dictation"]?["enabled"] == .bool(true))
        #expect(value["dictation"]?["stt"]?["provider"] == .string("openai"))
        #expect(value["dictation"]?["stt"]?["apiKey"] == .string("test-key-value"))
        #expect(value["dictation"]?["stt"]?["baseUrl"] == .null)
        #expect(value["dictation"]?["stt"]?["model"] == .string("whisper-1"))
        #expect(value["dictation"]?["stt"]?["language"] == nil)
        #expect(value["dictation"]?["stt"]?["voice"] == nil)
        #expect(value["voiceMode"] == nil)

        let ttsPatch = SpeechSettingsPatch(siteID: .voiceModeTTS, patch: SpeechSitePatch(voice: .some("alloy")))
        #expect(ttsPatch.jsonValue["voiceMode"]?["tts"]?["voice"] == .string("alloy"))
        #expect(ttsPatch.jsonValue["dictation"] == nil)
    }

    @Test func patchEncodesThroughDaemonConfigPatch() throws {
        var patch = DaemonConfigPatch()
        patch.features = SpeechSettingsPatch(dictationEnabled: false).jsonValue
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(patch))
        #expect(value["features"]?["dictation"]?["enabled"] == .bool(false))
        #expect(value["features"]?["voiceMode"] == nil)
        #expect(value["resumePrompt"] == nil)

        let empty = DaemonConfigPatch()
        let emptyValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(empty))
        #expect(emptyValue["features"] == nil)
    }

    @Test func decodesLocalSpeechModelListResponse() throws {
        let json = #"""
            {"requestId":"list-1","error":null,"models":[
              {"id":"parakeet","kind":"stt","label":"Parakeet","description":"English",
               "languages":["en"],"downloadSizeBytes":110000000,"isDefault":true,
               "inUse":true,"status":"installed"},
              {"id":"whisper","kind":"stt","label":"Whisper","description":"Multilingual",
               "languages":["en","de"],"downloadSizeBytes":1500000000,"isDefault":false,
               "inUse":false,"status":"downloading","receivedBytes":50000000,"totalBytes":200000000},
              {"id":"piper","kind":"tts","label":"Piper","description":"Voices",
               "languages":["en"],"downloadSizeBytes":60000000,"isDefault":true,
               "inUse":false,"status":"failed","error":"network down"},
              {"id":"future","kind":"stt","label":"Future","description":"",
               "languages":[],"downloadSizeBytes":1,"isDefault":false,"inUse":false,
               "status":"warming_up"}
            ]}
            """#
        let response = try JSONDecoder().decode(
            SpeechLocalModelsListRequest.Response.self, from: Data(json.utf8))
        #expect(response.requestId == "list-1")
        #expect(response.error == nil)
        #expect(response.models.count == 4)
        let whisper = try #require(response.models.first { $0.id == "whisper" })
        #expect(whisper.status == .downloading)
        #expect(whisper.receivedBytes == 50_000_000)
        #expect(whisper.totalBytes == 200_000_000)
        #expect(localModelState(of: whisper) == .downloading(percent: 25))
        #expect(isLocalModelBusy(whisper))
        let piper = try #require(response.models.first { $0.id == "piper" })
        #expect(localModelState(of: piper) == .failed(error: "network down"))
        #expect(!isLocalModelBusy(piper))
        let future = try #require(response.models.first { $0.id == "future" })
        #expect(future.status == .unknown("warming_up"))
        #expect(localModelState(of: future) == .notInstalled)
    }

    @Test func localModelRequestsEncodeWireNames() throws {
        let list = SpeechLocalModelsListRequest()
        #expect(SpeechLocalModelsListRequest.type == "speech.local_models.list.request")
        #expect(SpeechLocalModelsListRequest.responseType == "speech.local_models.list.response")
        let listValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(list))
        #expect(listValue["type"] == nil, "the envelope adds the type")

        let download = SpeechLocalModelsDownloadRequest(modelId: "whisper")
        #expect(SpeechLocalModelsDownloadRequest.type == "speech.local_models.download.request")
        let downloadValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(download))
        #expect(downloadValue["modelId"] == .string("whisper"))

        let delete = SpeechLocalModelsDeleteRequest(modelId: "whisper")
        #expect(SpeechLocalModelsDeleteRequest.type == "speech.local_models.delete.request")
        let deleteValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(delete))
        #expect(deleteValue["modelId"] == .string("whisper"))
    }

    @Test func openAIAndLocalResolutionMatchesUpstream() {
        #expect(resolveOpenAIModel(kind: .stt, model: nil) == "whisper-1")
        #expect(resolveOpenAIModel(kind: .tts, model: nil) == "tts-1")
        #expect(resolveOpenAIModel(kind: .stt, model: "custom") == "custom")
        #expect(resolveOpenAIVoice(nil) == "alloy")
        #expect(resolveOpenAIVoice("nova") == "nova")
        #expect(openAIModelOptions(kind: .stt, selected: "whisper-1").map(\.value)
            == ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"])
        #expect(openAIModelOptions(kind: .stt, selected: "custom-model").last?.value == "custom-model")
        #expect(openAIVoiceOptions(selected: "custom-voice").last?.value == "custom-voice")
        #expect(openAIVoiceOptions(selected: "alloy").contains { $0.value == "alloy" })

        let models = [
            LocalSpeechModel(id: "a", kind: "stt", label: "A", description: "", languages: [],
                             downloadSizeBytes: 1, isDefault: false, inUse: false, status: .installed),
            LocalSpeechModel(id: "b", kind: "stt", label: "B", description: "", languages: [],
                             downloadSizeBytes: 1, isDefault: true, inUse: false, status: .installed),
            LocalSpeechModel(id: "t", kind: "tts", label: "T", description: "", languages: [],
                             downloadSizeBytes: 1, isDefault: true, inUse: false, status: .installed),
        ]
        #expect(resolveLocalModel(kind: .stt, model: "a", models: models)?.id == "a")
        #expect(resolveLocalModel(kind: .stt, model: nil, models: models)?.id == "b")
        #expect(resolveLocalModel(kind: .tts, model: nil, models: models)?.id == "t")
        #expect(resolveLocalModel(kind: .stt, model: "missing", models: models) == nil)
    }

    @Test func summariesSayLocalOpenAIOrUnknown() {
        let models = [
            LocalSpeechModel(id: "a", kind: "stt", label: "Model A", description: "", languages: [],
                             downloadSizeBytes: 1, isDefault: true, inUse: true, status: .installed)
        ]
        let local = summarizeSpeechSite(
            siteID: .dictationSTT, site: SpeechSite(provider: .local), localModels: models, envOverrides: [:])
        #expect(local == .local(modelLabel: "Model A"))

        let openAI = summarizeSpeechSite(
            siteID: .dictationSTT, site: SpeechSite(provider: .openai, model: nil),
            localModels: [], envOverrides: [:])
        #expect(openAI == .openAI(model: "whisper-1", missingKey: true))

        let withKey = summarizeSpeechSite(
            siteID: .dictationSTT, site: SpeechSite(provider: .openai, hasApiKey: true),
            localModels: [], envOverrides: [:])
        #expect(withKey == .openAI(model: "whisper-1", missingKey: false))

        let envKey = summarizeSpeechSite(
            siteID: .dictationSTT, site: SpeechSite(provider: .openai),
            localModels: [], envOverrides: ["features.dictation.stt.apiKey": "ENV"])
        #expect(envKey == .openAI(model: "whisper-1", missingKey: false))

        let unknown = summarizeSpeechSite(
            siteID: .dictationSTT, site: SpeechSite(provider: .unknown("whisper-server")),
            localModels: [], envOverrides: [:])
        #expect(unknown == .unknown(provider: "whisper-server"))
    }

    @Test func envOverridesMakeFieldsReadOnlyExceptKeyAndBaseURL() {
        let sources = speechFieldSources(siteID: .dictationSTT, envOverrides: [
            "features.dictation.stt.model": "PASEO_DICTATION_STT_MODEL",
            "features.dictation.stt.apiKey": "PASEO_DICTATION_STT_API_KEY",
            "features.dictation.stt.baseUrl": "PASEO_DICTATION_STT_BASE_URL",
        ])
        #expect(sources[.model]?.readOnly == true)
        #expect(sources[.model]?.envVar == "PASEO_DICTATION_STT_MODEL")
        #expect(sources[.apiKey]?.readOnly == false, "a saved key beats the env fallback")
        #expect(sources[.baseUrl]?.readOnly == false)
        #expect(sources[.language]?.readOnly == false)
        #expect(sources[.provider]?.readOnly == false)
        #expect(SpeechSiteID.dictationSTT.fieldPath("model") == "features.dictation.stt.model")
        #expect(SpeechSiteID.voiceModeTTS.fieldPath("voice") == "features.voiceMode.tts.voice")
    }

    @Test func sizesAndLanguagesFormatLikeUpstream() {
        #expect(formatModelSize(bytes: 110_000_000) == "110 MB")
        #expect(formatModelSize(bytes: 1_500_000_000) == "1.5 GB")
        #expect(formatModelSize(bytes: 0) == "0 MB")
        #expect(formatModelSize(bytes: 999_499_999) == "999 MB")

        let many = (1...12).map { "code\($0)" }
        let formatted = formatLanguages(languages: many) { listed, count in "\(listed) AND \(count) MORE" }
        #expect(formatted.hasSuffix("AND 2 MORE"))
        #expect(!formatted.contains("code11"))
        #expect(formatLanguages(languages: ["en"]) { _ , _ in "MORE" }.isEmpty == false)
    }
}
