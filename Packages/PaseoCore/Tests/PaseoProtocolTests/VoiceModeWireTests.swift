import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

@Suite
struct VoiceModeWireTests {
    @Test func readsVoiceReadinessFromCapturedServerInfo() throws {
        let info = try JSONDecoder().decode(
            SessionPayloadEnvelope<ServerInfo>.self,
            from: Fixture.hostSettings("server_info")
        ).payload

        #expect(info.isVoiceAvailable)
        #expect(info.capabilities?.voice?.dictation.enabled == true)
        #expect(info.voiceReadiness?.enabled == true)
        #expect(info.capabilities?.voice?.voice.reason == "")
    }

    @Test func unknownDaemonShapesStayDecodable() throws {
        let json = #"""
            {"serverId":"s","capabilities":{"voice":{
              "dictation":{"enabled":true,"reason":""},
              "voice":{"enabled":false,"reason":"STT model missing","newField":3}}}}
            """#
        let info = try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
        #expect(info.isVoiceAvailable == false)
        #expect(info.capabilities?.voice?.voice.unavailableMessage == "STT model missing")
        #expect(info.capabilities?.voice?.voice.isUsable == false)
        #expect(info.capabilities?.voice?.dictation.isUsable == true)

        let noCaps = try JSONDecoder().decode(
            ServerInfo.self, from: Data(#"{"serverId":"s"}"#.utf8))
        #expect(noCaps.capabilities == nil)
        #expect(noCaps.isVoiceAvailable == false)
    }

    @Test func decodeSetVoiceModeResponseShapes() throws {
        let accepted = #"""
            {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":true,
             "error":null}
            """#
        let response = try JSONDecoder().decode(
            SetVoiceModeRequest.Response.self, from: Data(accepted.utf8))
        #expect(response.accepted)
        #expect(response.agentId == "agent-1")
        #expect(response.missingModelIds == nil)

        let declined = #"""
            {"requestId":"r","enabled":true,"agentId":null,"accepted":false,
             "error":"Voice backend is not ready","reasonCode":"stt_not_ready",
             "retryable":true,"missingModelIds":["stt-model-1"]}
            """#
        let rejected = try JSONDecoder().decode(
            SetVoiceModeRequest.Response.self, from: Data(declined.utf8))
        #expect(rejected.accepted == false)
        #expect(rejected.agentId == nil)
        #expect(rejected.error == "Voice backend is not ready")
        #expect(rejected.reasonCode == "stt_not_ready")
        #expect(rejected.retryable == true)
        #expect(rejected.missingModelIds == ["stt-model-1"])
    }

    @Test func setVoiceModeRequestEncodesAgentIdWhenPresent() throws {
        let enable = SetVoiceModeRequest(enabled: true, agentId: "agent-1")
        #expect(SetVoiceModeRequest.type == "set_voice_mode")
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(enable))
        #expect(value["enabled"] == .bool(true))
        #expect(value["agentId"] == .string("agent-1"))

        let disable = SetVoiceModeRequest(enabled: false)
        let disabled = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(disable))
        #expect(disabled["enabled"] == .bool(false))
        #expect(disabled["agentId"] == nil)
    }

    @Test func audioChunkAndPlayedEncodeWire() throws {
        let chunk = VoiceAudioChunk(audio: "QUFB", format: VoiceWire.pcmMimeType)
        #expect(VoiceAudioChunk.type == "voice_audio_chunk")
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(chunk))
        #expect(value["audio"] == .string("QUFB"))
        #expect(value["format"] == .string("audio/pcm;rate=16000;bits=16"))
        #expect(value["isLast"] == .bool(false))

        let played = AudioPlayed(id: "chunk-1")
        #expect(AudioPlayed.type == "audio_played")
        let playedValue = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(played))
        #expect(playedValue["id"] == .string("chunk-1"))
    }

    @Test func decodeAudioOutputPush() throws {
        let json = #"""
            {"audio":"QUFB","format":"pcm","id":"c1","isVoiceMode":true,
             "groupId":"g1","chunkIndex":2,"isLastChunk":false,"extra":1}
            """#
        let payload = try JSONDecoder().decode(AudioOutputPayload.self, from: Data(json.utf8))
        #expect(payload.id == "c1")
        #expect(payload.isVoiceMode)
        #expect(payload.groupId == "g1")
        #expect(payload.chunkIndex == 2)
        #expect(payload.isLastChunk == false)

        let sparse = #"""
            {"audio":"QQ==","format":"mp3","id":"c9","isVoiceMode":false,
             "groupId":null,"chunkIndex":null,"isLastChunk":null}
            """#
        let bare = try JSONDecoder().decode(AudioOutputPayload.self, from: Data(sparse.utf8))
        #expect(bare.groupId == nil)
        #expect(bare.chunkIndex == nil)
        #expect(bare.isLastChunk == nil)
    }

    @Test func decodeTranscriptionAndInputStatePushes() throws {
        let transcript = #"""
            {"text":"hello there","language":"en","duration":1200,
             "requestId":"t1","avgLogprob":-0.5,"isLowConfidence":true,
             "byteLength":44100,"format":"audio/pcm;rate=16000;bits=16"}
            """#
        let text = try JSONDecoder().decode(
            TranscriptionResultPayload.self, from: Data(transcript.utf8))
        #expect(text.text == "hello there")
        #expect(text.requestId == "t1")
        #expect(text.isLowConfidence == true)
        #expect(text.language == "en")

        let state = try JSONDecoder().decode(
            VoiceInputStatePayload.self, from: Data(#"{"isSpeaking":true}"#.utf8))
        #expect(state.isSpeaking)
    }

    @Test func playbackMimeTypeMatchesUpstream() {
        #expect(VoiceWire.playbackMimeType(format: "pcm") == "audio/pcm;rate=24000;bits=16")
        #expect(VoiceWire.playbackMimeType(format: "mp3") == "audio/mpeg")
        #expect(VoiceWire.playbackMimeType(format: "wav") == "audio/wav")
        #expect(VoiceWire.decodeAudio("not-base64!!").isEmpty)
        #expect(VoiceWire.decodeAudio("QUFB") == Data([65, 65, 65]))
        #expect(VoiceWire.encodePCM(Data([65, 65, 65])) == "QUFB")
    }
}
