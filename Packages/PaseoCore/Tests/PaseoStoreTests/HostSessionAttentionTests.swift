import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// M10 wiring: the session's event loop feeds attention events into `AttentionCenter` even when
/// no conversation for that agent is open.
@Suite @MainActor
struct HostSessionAttentionTests {
    private func streamAttention(
        agentId: String = "agent_1", reason: String = "finished", shouldNotify: Bool = true,
        timestamp: String = "2026-11-09T10:00:00Z", title: String = "Agent finished",
        workspaceId: String? = "wks_1"
    ) throws -> AgentStreamPayload {
        let workspace = workspaceId.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(
            AgentStreamPayload.self,
            from: Data(
                """
                {
                  "agentId": "\(agentId)",
                  "event": {
                    "type": "attention_required",
                    "provider": "pi",
                    "reason": "\(reason)",
                    "timestamp": "\(timestamp)",
                    "shouldNotify": \(shouldNotify),
                    "notification": {
                      "title": "\(title)",
                      "body": "Finished working.",
                      "data": {
                        "serverId": "srv_FIXTURE",
                        "workspaceId": \(workspace),
                        "agentId": "\(agentId)",
                        "reason": "\(reason)"
                      }
                    }
                  },
                  "timestamp": "\(timestamp)"
                }
                """.utf8))
    }

    private func terminalFrame(
        terminalId: String = "term_1", workspaceId: String? = "wks_1", shouldNotify: Bool = true
    ) -> Data {
        let workspace = workspaceId.map { "\"\($0)\"" } ?? "null"
        return Data(
            """
            {
              "type": "session",
              "message": {
                "type": "terminal_attention_required",
                "payload": {
                  "terminalId": "\(terminalId)",
                  "cwd": "/tmp/fixture-sandbox",
                  "workspaceId": \(workspace),
                  "reason": "needs_input",
                  "title": "Terminal needs input",
                  "body": "A shell command is waiting on you.",
                  "shouldNotify": \(shouldNotify)
                }
              }
            }
            """.utf8)
    }

    private func startedSession(_ client: FakeDaemonClient) async throws -> HostSession {
        let agents = try Load.agents()
        client.onFetchAgents { _ in agents }
        let session = HostSession(client: client)
        await session.start()
        return session
    }

    @Test func attentionStreamEventQueuesAnIntentWithoutAnOpenConversation() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)

        client.push(.agentStream(try streamAttention()))

        let queued = await eventually { session.attention.pending.count == 1 }
        #expect(queued)
        let intent = session.attention.pending.first
        #expect(intent?.agentId == "agent_1")
        #expect(intent?.workspaceId == "wks_1")
        #expect(intent?.title == "Agent finished")
    }

    @Test func theFocusedAgentIsNotQueued() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)
        session.attention.setFocusedAgent("agent_1")

        client.push(.agentStream(try streamAttention(agentId: "agent_1")))
        client.push(
            .agentStream(
                try streamAttention(
                    agentId: "agent_2", timestamp: "2026-11-09T10:00:01Z",
                    workspaceId: "wks_2")))

        let queued = await eventually { session.attention.pending.count == 1 }
        #expect(queued)
        #expect(session.attention.pending.first?.agentId == "agent_2")
    }

    @Test func terminalAttentionMessageQueuesAnIntent() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)

        client.push(
            .unhandled(
                messageType: "terminal_attention_required",
                raw: terminalFrame()))

        let queued = await eventually { session.attention.pending.count == 1 }
        #expect(queued)
        let intent = session.attention.pending.first
        #expect(intent?.terminalId == "term_1")
        #expect(intent?.workspaceId == "wks_1")
        #expect(intent?.title == "Terminal needs input")
    }

    @Test func terminalAttentionWithoutAWorkspaceUsesTheWatchedList() async throws {
        let client = FakeDaemonClient()
        let session = try await startedSession(client)
        // Pretend the terminal list for this workspace was opened before the attention arrived.
        client.push(
            .unhandled(
                messageType: "terminals_changed",
                raw: Data(
                    """
                    {
                      "type": "session",
                      "message": {
                        "type": "terminals_changed",
                        "payload": {
                          "workspaceId": "wks_from_list",
                          "terminals": [
                            {
                              "id": "term_9",
                              "name": "shell",
                              "cwd": "/tmp/fixture-sandbox",
                              "activity": { "state": "idle", "changedAt": 1 }
                            }
                          ]
                        }
                      }
                    }
                    """.utf8)))
        _ = await eventually { session.terminals.terminals(in: "wks_from_list").count == 1 }

        client.push(
            .unhandled(
                messageType: "terminal_attention_required",
                raw: terminalFrame(terminalId: "term_9", workspaceId: nil)))

        let queued = await eventually { session.attention.pending.count == 1 }
        #expect(queued)
        #expect(session.attention.pending.first?.workspaceId == "wks_from_list")
    }
}
