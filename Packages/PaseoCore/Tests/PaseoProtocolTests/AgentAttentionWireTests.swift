import Foundation
import PaseoProtocol
import Testing

/// The legacy `attention_required` stream event carries the daemon's notification plan. This
/// client is a legacy source, so this is the shape it actually receives.
@Suite struct AgentAttentionWireTests {
    private func payload(_ json: String) throws -> AgentStreamPayload {
        try JSONDecoder().decode(AgentStreamPayload.self, from: Data(json.utf8))
    }

    @Test func legacyAttentionEventKeepsItsNotificationPlan() throws {
        let stream = try payload(
            """
            {
              "agentId": "agent_1",
              "event": {
                "type": "attention_required",
                "provider": "pi",
                "reason": "permission",
                "timestamp": "2026-11-09T10:00:00.123Z",
                "shouldNotify": true,
                "notification": {
                  "title": "Agent needs permission",
                  "body": "Permission requested.",
                  "data": {
                    "serverId": "srv_1",
                    "workspaceId": "wks_1",
                    "agentId": "agent_1",
                    "reason": "permission"
                  }
                }
              },
              "timestamp": "2026-11-09T10:00:00.123Z"
            }
            """)

        guard case .attentionRequired(let reason) = stream.event else {
            Issue.record("expected an attention_required event")
            return
        }
        #expect(reason == "permission")
        let attention = try #require(stream.attention)
        #expect(attention.reason == .permission)
        #expect(attention.shouldNotify)
        #expect(attention.timestamp == "2026-11-09T10:00:00.123Z")
        #expect(attention.notification?.title == "Agent needs permission")
        #expect(attention.notification?.body == "Permission requested.")
        #expect(attention.notification?.data?.workspaceId == "wks_1")
        #expect(attention.notification?.data?.agentId == "agent_1")
    }

    @Test func attentionWithoutAPlanStillDecodesAndDefaultsToNotify() throws {
        let stream = try payload(
            """
            {
              "agentId": "agent_1",
              "event": { "type": "attention_required", "reason": "finished" },
              "timestamp": "2026-11-09T10:00:00Z"
            }
            """)

        let attention = try #require(stream.attention)
        #expect(attention.reason == .finished)
        #expect(attention.shouldNotify)
        #expect(attention.notification == nil)
    }

    @Test func unknownReasonDecodesAsUnknown() throws {
        let stream = try payload(
            """
            {
              "agentId": "agent_1",
              "event": {
                "type": "attention_required",
                "reason": "quota",
                "shouldNotify": false
              },
              "timestamp": "2026-11-09T10:00:00Z"
            }
            """)

        let attention = try #require(stream.attention)
        #expect(attention.reason == .unknown("quota"))
        #expect(attention.shouldNotify == false)
    }

    @Test func ordinaryStreamEventsHaveNoAttentionPlan() throws {
        let stream = try payload(
            """
            {
              "agentId": "agent_1",
              "event": { "type": "turn_completed", "turnId": "turn_1" },
              "timestamp": "2026-11-09T10:00:00Z",
              "seq": 12,
              "epoch": "epoch_1"
            }
            """)
        #expect(stream.attention == nil)
        #expect(stream.seq == 12)
        #expect(stream.epoch == "epoch_1")
    }

    @Test func modernTopLevelMessageDecodesToo() throws {
        let message = try JSONDecoder().decode(
            SessionPayloadEnvelope<AgentAttentionRequired>.self,
            from: Data(
                """
                {
                  "type": "session",
                  "message": {
                    "type": "agent_attention_required",
                    "payload": {
                      "agentId": "agent_1",
                      "reason": "finished",
                      "timestamp": "2026-11-09T10:00:00Z",
                      "shouldNotify": true
                    }
                  }
                }
                """.utf8))
        #expect(message.messageType == "agent_attention_required")
        #expect(message.payload.agentId == "agent_1")
        #expect(message.payload.reason == .finished)
    }
}
