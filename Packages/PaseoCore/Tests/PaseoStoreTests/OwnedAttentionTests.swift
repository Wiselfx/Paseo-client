import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// T17 follow-up: the two attention sources M10 added have to survive a modern socket, where the
/// daemon no longer broadcasts anything and skips the attention frame inside `agent_stream`.
///
/// - agent attention: only the `agent_attention_required` session event (`session.ts:1433-1444`
///   emits it, `:1457-1463` skips the stream frame for modern sources);
/// - terminal attention: only the `terminal_attention_required` session event
///   (`websocket-server.ts:3026-3078` publishes it through `publishToSource` →
///   `emitSubscribedEvent`, `session.ts:2431-2434`).
///
/// Both need a `session.events.set_subscription` that names the event *and* sets
/// `notifications: true`, otherwise `emitEventToOwner` rewrites `shouldNotify` to false
/// (`session.ts:9031-9054`) and `AttentionCenter` drops the intent.
@Suite @MainActor
struct OwnedAttentionTests {
    // MARK: Agent attention

    @Test func agentAttentionOnAModernSocketQueuesWithoutAnOpenConversation() async throws {
        let client = FakeDaemonClient()
        let agentId = try Load.fixtureAgentId()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { _ in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: "r", subscriptionId: "subs_events_1")
        }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.ownedEvents.subscriptionId == "subs_events_1" })

        client.push(
            .unhandled(
                messageType: "agent_attention_required",
                raw: try Self.attentionFrame(agentId: agentId)))

        #expect(await eventually { session.attention.pending.count == 1 })
        let intent = session.attention.pending.first
        #expect(intent?.agentId == agentId)
        #expect(intent?.reason == "finished")
        #expect(intent?.title == "Agent finished")
        // No conversation was opened: nothing asked for that agent's timeline.
        #expect(client.requests(SetAgentTimelineSubscriptionRequest.self).isEmpty)
    }

    @Test func theEventSubscriptionAsksForNotifications() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { _ in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: "r", subscriptionId: "subs_events_1")
        }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.ownedEvents.subscriptionId == "subs_events_1" })

        // The workspace directory sends its own event subscription for project/checkout
        // pushes, so pick ours out by content.
        let request = try #require(
            client.requests(SessionEventsSetSubscriptionRequest.self).first {
                $0.events.contains("agent_attention_required")
            })
        #expect(request.notifications == true)
        #expect(request.events.contains("agent_attention_required"))
        #expect(request.events.contains("terminal_attention_required"))
    }

    @Test func aModernSocketDropsTheShouldNotifyFalseCopy() async throws {
        // A daemon that has not been told `notifications: true` still sends the event, but with
        // `shouldNotify: false`. That must not queue a local notification.
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { _ in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: "r", subscriptionId: "subs_events_1")
        }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.ownedEvents.subscriptionId == "subs_events_1" })

        client.push(
            .unhandled(
                messageType: "agent_attention_required",
                raw: try Self.attentionFrame(shouldNotify: false)))
        // Let the loop drain before asserting nothing was queued.
        _ = await eventually { session.serverInfo != nil }
        #expect(session.attention.pending.isEmpty)
    }

    // MARK: Terminal attention

    @Test func terminalAttentionOnAModernSocketQueuesWithoutADirectorySubscription() async throws {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { _ in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: "r", subscriptionId: "subs_events_1")
        }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.ownedEvents.subscriptionId == "subs_events_1" })

        client.push(
            .unhandled(
                messageType: "terminal_attention_required",
                raw: try Self.terminalAttentionFrame()))

        #expect(await eventually { session.attention.pending.count == 1 })
        #expect(session.attention.pending.first?.terminalId == "term_1")
        #expect(session.attention.pending.first?.workspaceId == "wks_1")
        // Attention is a session event: it needs no terminal directory subscription.
        #expect(session.terminals.terminals(in: "wks_1").isEmpty)
    }

    @Test func attentionFromBothShapesIsDeduped() async throws {
        // A legacy socket can see the same attention twice: once as the session event and once
        // inside `agent_stream`. `AttentionCenter` keeps one intent per destination.
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.on(ProjectListRequest.self) { _ in try Load.projectList() }
        client.on(FetchWorkspacesRequest.self) { _ in try Load.workspaceDirectory() }
        client.on(SessionEventsSetSubscriptionRequest.self) { _ in
            SessionEventsSetSubscriptionRequest.Response(
                requestId: "r", subscriptionId: "subs_events_1")
        }
        let session = HostSession(client: client)
        await session.start()
        client.push(.connected(try Load.serverInfo()))
        #expect(await eventually { session.ownedEvents.subscriptionId == "subs_events_1" })

        // Both shapes name the same agent, so the second is the same destination.
        client.push(
            .unhandled(
                messageType: "agent_attention_required",
                raw: try Self.attentionFrame(agentId: "agent_1")))
        #expect(await eventually { session.attention.pending.count == 1 })
        client.push(.agentStream(try Self.streamAttention()))
        _ = await eventually { session.serverInfo != nil }
        #expect(session.attention.pending.count == 1)
    }

    // MARK: Fixtures

    nonisolated private static func attentionFrame(
        agentId: String = "agent_1", shouldNotify: Bool = true
    ) throws -> Data {
        Data(
            """
            {
              "type": "session",
              "message": {
                "type": "agent_attention_required",
                "payload": {
                  "agentId": "\(agentId)",
                  "reason": "finished",
                  "timestamp": "2026-11-09T10:00:00Z",
                  "shouldNotify": \(shouldNotify),
                  "notification": {
                    "title": "Agent finished",
                    "body": "Finished working.",
                    "data": {
                      "serverId": "srv_FIXTURE",
                      "workspaceId": "wks_1",
                      "agentId": "\(agentId)"
                    }
                  }
                }
              }
            }
            """.utf8)
    }

    nonisolated private static func terminalAttentionFrame() throws -> Data {
        Data(
            """
            {
              "type": "session",
              "message": {
                "type": "terminal_attention_required",
                "payload": {
                  "terminalId": "term_1",
                  "cwd": "/tmp/fixture-sandbox",
                  "workspaceId": "wks_1",
                  "reason": "needs_input",
                  "title": "Terminal needs input",
                  "body": "A terminal is waiting for input.",
                  "shouldNotify": true
                }
              }
            }
            """.utf8)
    }

    nonisolated private static func streamAttention() throws -> AgentStreamPayload {
        try JSONDecoder().decode(
            AgentStreamPayload.self,
            from: Data(
                """
                {
                  "agentId": "agent_1",
                  "event": {
                    "type": "attention_required",
                    "provider": "pi",
                    "reason": "finished",
                    "timestamp": "2026-11-09T10:00:00Z",
                    "shouldNotify": true,
                    "notification": {
                      "title": "Agent finished",
                      "body": "Finished working.",
                      "data": {
                        "serverId": "srv_FIXTURE",
                        "workspaceId": "wks_1",
                        "agentId": "agent_1"
                      }
                    }
                  },
                  "timestamp": "2026-11-09T10:00:00Z"
                }
                """.utf8))
    }
}
