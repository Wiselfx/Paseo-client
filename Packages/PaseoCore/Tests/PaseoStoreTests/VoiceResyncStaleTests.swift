import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The `.connected` resync is fire-and-forget (it must never gate the directory), so its
/// `set_voice_mode` round trip can land after the socket moved on. A stale answer must not
/// write anything into the lane: the generation that produced it is no longer current.
@Suite @MainActor
struct VoiceResyncStaleTests {
    private func serverInfo() throws -> ServerInfo {
        try JSONDecoder().decode(
            ServerInfo.self,
            from: Data(#"""
                {"serverId":"s","capabilities":{"voice":{
                  "dictation":{"enabled":true,"reason":""},
                  "voice":{"enabled":true,"reason":""}}}}
                """#.utf8))
    }

    private func enableResponse(accepted: Bool, error: String?) throws
        -> SetVoiceModeRequest.Response
    {
        let errorJSON = error.map { "\"\($0)\"" } ?? "null"
        let json = """
            {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":\(accepted),
             "error":\(errorJSON)}
            """
        return try JSONDecoder().decode(SetVoiceModeRequest.Response.self, from: Data(json.utf8))
    }

    @Test func staleResyncRefusalIsIgnoredAfterReconnect() async throws {
        let client = FakeDaemonClient()
        let session = VoiceModeSession(client: client)
        session.serverInfoChanged(try serverInfo())

        client.onSend(SetVoiceModeRequest.self) { _ in
            try JSONDecoder().decode(
                SetVoiceModeRequest.Response.self,
                from: Data(#"""
                    {"requestId":"r","enabled":true,"agentId":"agent-1","accepted":true,
                     "error":null}
                    """#.utf8))
        }
        #expect(await session.start(agentId: "agent-1"))

        // The resync answers late, and refuses: applying it would clear the lane.
        let refusal = try enableResponse(accepted: false, error: "Voice unavailable")
        client.onSend(SetVoiceModeRequest.self) { _ in
            try? await Task.sleep(for: .milliseconds(80))
            return refusal
        }
        let info = try serverInfo()
        let before = client.requests(SetVoiceModeRequest.self).count
        let resync = Task { await session.handle(connection: .connected(info)) }
        for _ in 0..<50 {
            await Task.yield()
            if client.requests(SetVoiceModeRequest.self).count > before { break }
        }
        // The socket moves on while the resync's request is in flight.
        await session.handle(connection: .reconnecting(attempt: 1, lastError: .timeout))
        await resync.value

        #expect(session.error == nil, "the stale refusal must not surface")
        #expect(!session.isVoiceSwitching)
        #expect(session.isVoiceMode)
        #expect(session.phase == .listening)
    }
}
