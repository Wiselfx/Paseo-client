import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// Drives `VoiceModeSession` with `FakeDaemonClient`.
@Suite @MainActor
struct VoiceModeSessionTests {
    private func serverInfo(voice: String) throws -> ServerInfo {
        let json = """
            {"serverId":"s","capabilities":{"voice":{
              "dictation":{"enabled":true,"reason":""},
              "voice":\(voice)}}}
            """
        return try JSONDecoder().decode(ServerInfo.self, from: Data(json.utf8))
    }

    private func setVoiceResponse(accepted: Bool = true) -> SetVoiceModeRequest.Response {
        try! JSONDecoder().decode(
            SetVoiceModeRequest.Response.self,
            from: Data(#"""
                {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":\#(accepted),
                 "error":null}
                """#.utf8))
    }

    private func makeSession(_ client: FakeDaemonClient, voice: String = #"{"enabled":true,"reason":""}"#) throws
        -> VoiceModeSession
    {
        let session = VoiceModeSession(client: client)
        session.serverInfoChanged(try serverInfo(voice: voice))
        return session
    }

    private func startable(_ client: FakeDaemonClient) {
        client.onSend(SetVoiceModeRequest.self) { _ in
            try! JSONDecoder().decode(
                SetVoiceModeRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":true,
                     "error":null}
                    """#.utf8))
        }
    }

    private func turnPayload(agentId: String, type: String) throws -> AgentStreamPayload {
        let json = """
            {"agentId":"\(agentId)","timestamp":"2026-11-08T12:00:00.000Z",
             "event":{"type":"\(type)","turnId":"t1"}}
            """
        return try JSONDecoder().decode(AgentStreamPayload.self, from: Data(json.utf8))
    }

    /// Waits until a fire-and-forget message (voice chunk / ack) lands in the fake client.
    /// The store sends those on a detached task, exactly like upstream's fire-and-forget.
    private func waitForSent(_ typeName: String, in client: FakeDaemonClient) async {
        for _ in 0..<50 {
            await Task.yield()
            if client.messages.contains(where: { String(describing: type(of: $0)) == typeName }) { return }
        }
    }

    private func serverInfoConnected() throws -> ServerInfo {
        try JSONDecoder().decode(ServerInfo.self, from: Data(#"{"serverId":"s","capabilities":{"voice":{"dictation":{"enabled":true,"reason":""},"voice":{"enabled":true,"reason":""}}}}"#.utf8))
    }

    private func audioPayload(id: String, group: String, index: Int, last: Bool) -> AudioOutputPayload {
        AudioOutputPayload(
            audio: "QUFB", format: "pcm", id: id, isVoiceMode: true,
            groupId: group, chunkIndex: index, isLastChunk: last)
    }

    @Test func startRefusedUntilDaemonSaysVoiceIsUsable() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client, voice: #"{"enabled":false,"reason":"No STT model"}"#)
        startable(client)

        let started = await session.start(agentId: "agent-1")

        #expect(!started)
        #expect(session.error == "No STT model")
        #expect(session.phase == .disabled)
        #expect(client.requests(SetVoiceModeRequest.self).isEmpty)
    }

    @Test func startEntersVoiceAndStreamsMicPCM() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)

        let started = await session.start(agentId: "agent-1")

        #expect(started)
        #expect(session.phase == .listening)
        #expect(session.activeAgentId == "agent-1")
        #expect(session.isVoiceMode(for: "agent-1"))
        #expect(session.error == nil)
        let sent = try #require(client.requests(SetVoiceModeRequest.self).first)
        #expect(sent.enabled)
        #expect(sent.agentId == "agent-1")

        session.handleCapturePCM(Data([0x41, 0x41, 0x41]))
        await waitForSent("VoiceAudioChunk", in: client)
        let chunks = client.messages.compactMap { $0 as? VoiceAudioChunk }
        #expect(chunks.count == 1)
        #expect(chunks.first?.audio == "QUFB")
        #expect(chunks.first?.format == "audio/pcm;rate=16000;bits=16")
        #expect(chunks.first?.isLast == false)
    }

    @Test func rejectedStartSurfacesReasonCodeAndMissingModels() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        client.onSend(SetVoiceModeRequest.self) { _ in
            try! JSONDecoder().decode(
                SetVoiceModeRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","enabled":true,"agentId":null,"accepted":false,
                     "error":"Speech backend is not ready","reasonCode":"stt_not_ready",
                     "retryable":true,"missingModelIds":["stt-model-1"]}
                    """#.utf8))
        }

        let started = await session.start(agentId: "agent-1")

        #expect(!started)
        #expect(session.error == "Speech backend is not ready (stt_not_ready)")
        #expect(session.missingModelIds == ["stt-model-1"])
        #expect(session.phase == .disabled)
    }

    @Test func switchingAgentsKillsThePreviousLane() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        let switched = await session.start(agentId: "agent-2")

        #expect(switched)
        let sent = client.requests(SetVoiceModeRequest.self)
        #expect(sent.count == 3)
        #expect(sent[1].enabled == false)
        #expect(sent[2].enabled == true && sent[2].agentId == "agent-2")
        #expect(session.activeAgentId == "agent-2")
    }

    @Test func muteDropsChunksAndZeroesVolume() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handleCaptureVolume(1, now: Date(timeIntervalSince1970: 1000))
        session.setMuted(true)
        #expect(session.volume == 0)

        session.handleCapturePCM(Data([1, 2, 3]))
        #expect(client.messages.compactMap { $0 as? VoiceAudioChunk }.isEmpty)

        session.setMuted(false)
        session.handleCapturePCM(Data([1, 2, 3]))
        await waitForSent("VoiceAudioChunk", in: client)
        #expect(client.messages.compactMap { $0 as? VoiceAudioChunk }.count == 1)
    }

    @Test func volumeSmoothingMatchesUpstream() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handleCaptureVolume(1, now: Date(timeIntervalSince1970: 0))
        // attack: 0 + (1-0)*0.35
        #expect(session.volume == 0.35)
        // big enough change: republishes on the epsilon rule even before 120 ms
        session.handleCaptureVolume(1, now: Date(timeIntervalSince1970: 0.05))
        #expect(abs(session.volume - 0.5775) < 0.001)
        session.handleCaptureVolume(0, now: Date(timeIntervalSince1970: 0.2))
        #expect(abs(session.volume - 0.474) < 0.01)
    }

    @Test func audioQueuePlaysInOrderAndAcks() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        // Chunk 1 arrives before chunk 0: nothing to play yet.
        session.handleAudioOutput(audioPayload(id: "c1", group: "g", index: 1, last: false))
        #expect(session.nextAudioChunk == nil)
        session.handleAudioOutput(audioPayload(id: "c0", group: "g", index: 0, last: false))
        #expect(session.nextAudioChunk?.id == "c0")
        #expect(session.phase == .playing)

        session.didPlayChunk(id: "c0")
        #expect(session.nextAudioChunk?.id == "c1")

        session.handleAudioOutput(audioPayload(id: "c2", group: "g", index: 2, last: true))
        session.didPlayChunk(id: "c1")
        session.didPlayChunk(id: "c2")

        // acks are fire-and-forget; wait for all three to land
        for _ in 0..<50 {
            await Task.yield()
            if client.messages.compactMap({ $0 as? AudioPlayed }).count >= 3 { break }
        }
        let acked = client.messages.compactMap { $0 as? AudioPlayed }.map(\.id).sorted()
        #expect(acked == ["c0", "c1", "c2"])
        #expect(session.nextAudioChunk == nil)
        #expect(session.phase == .listening)
        #expect(!session.isAssistantAudioPlaying)
    }

    @Test func nonVoiceLaneAudioIsDropped() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handleAudioOutput(
            AudioOutputPayload(audio: "QQ==", format: "pcm", id: "other", isVoiceMode: false))

        #expect(session.nextAudioChunk == nil)
        #expect(client.messages.compactMap { $0 as? AudioPlayed }.isEmpty)
    }

    @Test func secondUtteranceQueuesBehindTheFirst() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handleAudioOutput(audioPayload(id: "a0", group: "ga", index: 0, last: true))
        session.handleAudioOutput(audioPayload(id: "b0", group: "gb", index: 0, last: true))
        #expect(session.nextAudioChunk?.id == "a0")

        session.didPlayChunk(id: "a0")
        #expect(session.nextAudioChunk?.id == "b0")
        #expect(session.phase == .playing)
    }

    @Test func serverSpeechInterruptsPlayback() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")
        session.handleAudioOutput(audioPayload(id: "a0", group: "ga", index: 0, last: true))
        #expect(session.nextAudioChunk != nil)
        let stopsBefore = session.playbackStopRequested

        session.handleVoiceInputState(VoiceInputStatePayload(isSpeaking: true))

        #expect(session.isSpeaking)
        #expect(session.nextAudioChunk == nil)
        #expect(session.playbackStopRequested == stopsBefore + 1)
    }

    @Test func transcriptionFlipsWaitingAndListening() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handleTranscription(TranscriptionResultPayload(text: "hello"))
        // text is required by the wire; decode through JSON for the full payload.
        #expect(session.phase == .waiting)

        session.handleTranscription(TranscriptionResultPayload(text: "   "))
        #expect(session.phase == .listening)
    }

    @Test func transcriptJSONDecodesThroughTheEnvelope() throws {
        let payload = try JSONDecoder().decode(
            SessionPayloadEnvelope<TranscriptionResultPayload>.self,
            from: Data(#"""
                {"type":"session","message":{"type":"transcription_result",
                 "payload":{"text":"hello agent","requestId":"t1"}}}
                """#.utf8)).payload
        #expect(payload.text == "hello agent")
    }

    @Test func turnEventsMovePhasesButNeverInterruptPlayback() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        session.handle(agentStream: try turnPayload(agentId: "agent-1", type: "turn_started"))
        #expect(session.phase == .waiting)
        session.handle(agentStream: try turnPayload(agentId: "agent-1", type: "turn_completed"))
        #expect(session.phase == .listening)

        // events for other agents don't touch the phase
        session.handle(agentStream: try turnPayload(agentId: "other", type: "turn_started"))
        #expect(session.phase == .listening)

        session.handleAudioOutput(audioPayload(id: "a0", group: "ga", index: 0, last: true))
        #expect(session.phase == .playing)
        session.handle(agentStream: try turnPayload(agentId: "agent-1", type: "turn_completed"))
        #expect(session.phase == .playing)
    }

    @Test func lateAckAfterStopDoesNotCrashNorAck() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")
        session.handleAudioOutput(audioPayload(id: "a0", group: "ga", index: 0, last: false))
        #expect(session.nextAudioChunk?.id == "a0")

        await session.stop()
        // The engine's in-flight completion fires after the stop cleared the queue:
        // this must be a silent no-op (no force-unwrap crash, no stale ack).
        session.didPlayChunk(id: "a0")
        session.didFailChunk(id: "a0")

        for _ in 0..<20 { await Task.yield() }
        #expect(session.phase == .disabled)
        #expect(client.messages.compactMap { $0 as? AudioPlayed }.isEmpty)
    }

    @Test func stopDuringStartDropsTheLateStartResponse() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        client.onSend(SetVoiceModeRequest.self) { request in
            if request.enabled {
                // Hold the enable response until the test's stop() has run.
                try? await Task.sleep(for: .milliseconds(80))
            }
            return try! JSONDecoder().decode(
                SetVoiceModeRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","enabled":\#(request.enabled),"agentId":"agent-1",
                     "accepted":true,"error":null}
                    """#.utf8))
        }
        let startTask = Task { await session.start(agentId: "agent-1") }
        for _ in 0..<50 {
            await Task.yield()
            if session.phase == .starting { break }
        }
        #expect(session.phase == .starting)

        let stopped = await session.stop()
        let started = await startTask.value

        #expect(stopped)
        #expect(!started, "the start response arrived after the stop generation bump")
        #expect(session.phase == .disabled)
        #expect(session.activeAgentId == nil)
        #expect(client.requests(SetVoiceModeRequest.self).last?.enabled == false)
    }

    @Test func failedConnectionDoesFullLocalTeardown() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")
        session.handleAudioOutput(audioPayload(id: "a0", group: "ga", index: 0, last: true))
        #expect(session.nextAudioChunk != nil)
        let stopsBefore = session.playbackStopRequested

        await session.handle(connection: .failed(.timeout))

        #expect(session.phase == .disabled)
        #expect(session.activeAgentId == nil)
        #expect(session.nextAudioChunk == nil)
        #expect(!session.isVoiceMode)
        #expect(session.playbackStopRequested == stopsBefore + 1)
    }

    @Test func stopCancelsTheTurnThenLeavesTheLane() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        client.onSend(CancelAgentRequest.self) { _ in
            try! JSONDecoder().decode(
                CancelAgentRequest.Response.self,
                from: Data(#"{"requestId":"r","agentId":"agent-1","error":null}"#.utf8))
        }
        await session.start(agentId: "agent-1")
        session.handle(agentStream: try turnPayload(agentId: "agent-1", type: "turn_started"))
        #expect(session.phase == .waiting)

        let stopped = await session.stop()

        #expect(stopped)
        #expect(session.phase == .disabled)
        #expect(session.activeAgentId == nil)
        #expect(client.requests(CancelAgentRequest.self).map(\.agentId) == ["agent-1"])
        let sent = client.requests(SetVoiceModeRequest.self)
        #expect(sent.count == 2)
        #expect(sent[1].enabled == false)
        session.handleCapturePCM(Data([1]))
        #expect(client.messages.compactMap { $0 as? VoiceAudioChunk }.isEmpty)
    }

    @Test func disconnectBreaksTheTransportAndReconnectResyncs() async throws {
        let client = FakeDaemonClient()
        let session = try makeSession(client)
        startable(client)
        await session.start(agentId: "agent-1")

        await session.handle(connection: .reconnecting(attempt: 1, lastError: .timeout))
        session.handleCapturePCM(Data([1, 2, 3]))
        #expect(client.messages.compactMap { $0 as? VoiceAudioChunk }.isEmpty)

        await session.handle(connection: .connected(try serverInfoConnected()))
        let sent = client.requests(SetVoiceModeRequest.self)
        #expect(sent.count == 2)
        #expect(sent[1].enabled && sent[1].agentId == "agent-1")
        session.handleCapturePCM(Data([1, 2, 3]))
        await waitForSent("VoiceAudioChunk", in: client)
        #expect(client.messages.compactMap { $0 as? VoiceAudioChunk }.count == 1)
    }
}
