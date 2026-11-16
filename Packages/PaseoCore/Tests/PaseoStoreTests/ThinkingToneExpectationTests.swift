import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The thinking tone (upstream `canPlayCue`): the UI may only play it while the lane is
/// waiting for a reply and the daemon hears no speech. The engine owns the timing; the
/// store owns this gate.
@Suite @MainActor
struct ThinkingToneExpectationTests {
    private func serverInfo() throws -> ServerInfo {
        try JSONDecoder().decode(
            ServerInfo.self,
            from: Data(#"""
                {"serverId":"s","capabilities":{"voice":{
                  "dictation":{"enabled":true,"reason":""},
                  "voice":{"enabled":true,"reason":""}}}}
                """#.utf8))
    }

    private func makeSession(_ client: FakeDaemonClient) throws -> VoiceModeSession {
        client.onSend(SetVoiceModeRequest.self) { _ in
            try JSONDecoder().decode(
                SetVoiceModeRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":true,
                     "error":null}
                    """#.utf8))
        }
        let session = VoiceModeSession(client: client)
        session.serverInfoChanged(try serverInfo())
        return session
    }

    @Test func expectedOnlyWhileWaitingAndSilent() async throws {
        let session = try makeSession(FakeDaemonClient())
        #expect(!session.isThinkingToneExpected, "no voice mode, no tone")
        #expect(await session.start(agentId: "agent-1"))
        #expect(session.phase == .listening)
        #expect(!session.isThinkingToneExpected, "listening is not a wait")

        // A non-empty transcript flips the lane to `.waiting` (turn in progress).
        session.handleTranscription(TranscriptionResultPayload(text: "hello"))
        #expect(session.phase == .waiting)
        #expect(session.isThinkingToneExpected)

        // Server VAD wins over the phase: while the user is speaking there is no wait.
        session.handleVoiceInputState(VoiceInputStatePayload(isSpeaking: true))
        #expect(!session.isThinkingToneExpected)
        session.handleVoiceInputState(VoiceInputStatePayload(isSpeaking: false))
        #expect(session.isThinkingToneExpected)

        // An empty transcript means the turn ended: back to listening, no tone.
        session.handleTranscription(TranscriptionResultPayload(text: "   "))
        #expect(session.phase == .listening)
        #expect(!session.isThinkingToneExpected)
    }

    @Test func stopsAsSoonAsTheReplyPlays() async throws {
        let session = try makeSession(FakeDaemonClient())
        #expect(await session.start(agentId: "agent-1"))
        session.handleTranscription(TranscriptionResultPayload(text: "hello"))
        #expect(session.isThinkingToneExpected)

        // First audio chunk of the reply starts playback (`onAssistantAudioStarted`).
        session.handleAudioOutput(
            AudioOutputPayload(
                audio: "QUFB", format: "pcm;rate=24000", id: "a0", isVoiceMode: true,
                groupId: "g-1", chunkIndex: 0, isLastChunk: true))
        #expect(session.phase == .playing)
        #expect(!session.isThinkingToneExpected)

        // After the reply finishes, a still-active turn is a wait again.
        session.didPlayChunk(id: "a0")
        #expect(session.isThinkingToneExpected)
    }

    @Test func stopsOnLocalStop() async throws {
        let session = try makeSession(FakeDaemonClient())
        #expect(await session.start(agentId: "agent-1"))
        session.handleTranscription(TranscriptionResultPayload(text: "hello"))
        #expect(session.isThinkingToneExpected)

        _ = await session.stop()
        #expect(session.phase == .disabled)
        #expect(!session.isThinkingToneExpected)
    }
}
