import Foundation
import PaseoProtocol
import Testing

@testable import PaseoStore

@Suite @MainActor
struct AttentionCenterTests {
    private func notification(
        title: String = "Agent finished", body: String = "Finished working.",
        workspaceId: String? = "wks_1"
    ) -> AgentAttentionNotification {
        AgentAttentionNotification(
            title: title, body: body,
            data: AgentAttentionNotificationData(
                serverId: "srv_FIXTURE", workspaceId: workspaceId, agentId: "agent_1",
                reason: .finished))
    }

    private func terminal(_ json: String) throws -> TerminalAttentionRequired {
        try JSONDecoder().decode(
            SessionPayloadEnvelope<TerminalAttentionRequired>.self, from: Data(json.utf8)
        ).payload
    }

    private func terminalPayload(
        shouldNotify: Bool = true, workspaceId: String? = "wks_1"
    ) throws -> TerminalAttentionRequired {
        let workspace = workspaceId.map { "\"\($0)\"" } ?? "null"
        return try terminal(
            """
            {
              "type": "session",
              "message": {
                "type": "terminal_attention_required",
                "payload": {
                  "terminalId": "term_1",
                  "cwd": "/tmp/fixture-sandbox",
                  "workspaceId": \(workspace),
                  "reason": "needs_input",
                  "title": "Terminal needs input",
                  "body": "A shell command is waiting on you.",
                  "shouldNotify": \(shouldNotify)
                }
              }
            }
            """)
    }

    @Test func agentAttentionUsesTheDaemonsCopy() {
        let center = AttentionCenter()
        let intent = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:00Z",
                shouldNotify: true, notification: notification()))

        #expect(intent?.title == "Agent finished")
        #expect(intent?.body == "Finished working.")
        #expect(intent?.target.kind == .agent)
        #expect(intent?.agentId == "agent_1")
        #expect(intent?.workspaceId == "wks_1")
        #expect(intent?.reason == "finished")
        #expect(center.pending.count == 1)
    }

    @Test func agentAttentionFallsBackWhenTheDaemonSendsNoCopy() {
        let center = AttentionCenter()
        let permission = center.receive(
            agentId: "agent_1", workspaceId: nil,
            attention: AgentAttentionDetail(reason: .permission))
        #expect(permission?.title == "Agent needs permission")
        #expect(permission?.body == "Permission requested.")
        #expect(permission?.workspaceId == nil)

        let finished = center.receive(
            agentId: "agent_2", workspaceId: nil,
            attention: AgentAttentionDetail(reason: .finished))
        #expect(finished?.title == "Agent finished")
        #expect(finished?.body == "Finished working.")
    }

    @Test func pureErrorsAreNeverNotified() {
        let center = AttentionCenter()
        let intent = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .error, timestamp: "2026-11-09T10:00:00Z", shouldNotify: true,
                notification: notification(title: "Agent needs attention")))
        #expect(intent == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func anotherClientsNotificationIsHonoured() {
        let center = AttentionCenter()
        let intent = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(reason: .finished, shouldNotify: false))
        #expect(intent == nil)
        #expect(center.pending.isEmpty)
    }

    @Test func theAgentOnScreenIsSuppressed() {
        let center = AttentionCenter()
        center.setFocusedAgent("agent_1")

        let suppressed = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:00Z", shouldNotify: true))
        #expect(suppressed == nil)
        #expect(center.pending.isEmpty)

        let other = center.receive(
            agentId: "agent_2", workspaceId: "wks_2",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:01Z", shouldNotify: true))
        #expect(other?.agentId == "agent_2")
        #expect(center.pending.count == 1)

        center.setFocusedAgent(nil)
        let afterLeaving = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:02Z", shouldNotify: true))
        #expect(afterLeaving?.agentId == "agent_1")
    }

    @Test func duplicateAndOlderEventsAreDropped() {
        let center = AttentionCenter()
        _ = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:05Z", shouldNotify: true,
                notification: notification(title: "First")))

        let duplicate = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:05Z", shouldNotify: true,
                notification: notification(title: "Duplicate")))
        #expect(duplicate == nil)
        let older = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:04Z", shouldNotify: true,
                notification: notification(title: "Older")))
        #expect(older == nil)
        #expect(center.pending.count == 1)
        #expect(center.pending.first?.title == "First")
    }

    @Test func aNewerEventReplacesTheQueuedNotificationForTheSameAgent() {
        let center = AttentionCenter()
        _ = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:05Z", shouldNotify: true,
                notification: notification(title: "Agent finished")))
        _ = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .permission, timestamp: "2026-11-09T10:00:06Z", shouldNotify: true,
                notification: notification(title: "Agent needs permission")))

        #expect(center.pending.count == 1)
        #expect(center.pending.first?.title == "Agent needs permission")
        #expect(center.pending.first?.reason == "permission")
    }

    @Test func terminalAttentionUsesTheDaemonsCopyAndWorkspace() throws {
        let center = AttentionCenter()
        let payload = try terminalPayload()
        let intent = center.receive(terminal: payload)

        #expect(intent?.title == "Terminal needs input")
        #expect(intent?.body == "A shell command is waiting on you.")
        #expect(intent?.target.kind == .terminal)
        #expect(intent?.terminalId == "term_1")
        #expect(intent?.workspaceId == "wks_1")
        #expect(intent?.reason == "needs_input")
    }

    @Test func terminalAttentionFallsBackToTheCallersWorkspaceAndIsSuppressedWhenAsked() throws {
        let center = AttentionCenter()
        let noWorkspace = try terminalPayload(workspaceId: nil)
        let intent = center.receive(terminal: noWorkspace, workspaceId: "wks_from_cwd")
        #expect(intent?.workspaceId == "wks_from_cwd")

        let muted = try terminalPayload(shouldNotify: false)
        let suppressed = center.receive(terminal: muted)
        #expect(suppressed == nil)
    }

    @Test func drainReturnsAndClearsWhileKeepingWatermarks() throws {
        let center = AttentionCenter()
        _ = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:00Z", shouldNotify: true))
        _ = center.receive(terminal: try terminalPayload())

        #expect(center.pending.count == 2)
        let drained = center.drain()
        #expect(drained.count == 2)
        #expect(center.pending.isEmpty)

        let replay = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(
                reason: .finished, timestamp: "2026-11-09T10:00:00Z", shouldNotify: true))
        #expect(replay == nil, "a drained event must not come back on replay")
    }

    @Test func clearDropsEverythingWithoutReturningIt() {
        let center = AttentionCenter()
        _ = center.receive(
            agentId: "agent_1", workspaceId: "wks_1",
            attention: AgentAttentionDetail(reason: .finished))
        center.clear()
        #expect(center.pending.isEmpty)
    }

    @Test func targetUserInfoRoundTrips() throws {
        let agent = AttentionTarget.agent("agent_1", workspaceId: "wks_1")
        let restoredAgent = try #require(AttentionTarget(userInfo: agent.userInfo))
        #expect(restoredAgent == agent)

        let terminal = AttentionTarget.terminal("term_1")
        let restoredTerminal = try #require(AttentionTarget(userInfo: terminal.userInfo))
        #expect(restoredTerminal == terminal)

        #expect(AttentionTarget(userInfo: ["kind": "agent"]) == nil)
        #expect(AttentionTarget(userInfo: ["kind": "elsewhere", "agentId": "a"]) == nil)
    }
}
