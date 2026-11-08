import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

/// Some requests are answered by an event-shaped message rather than a `*_response`: agent
/// creation uses `status`, permissions use `agent_permission_resolved`, archive uses the
/// `agent_archived` broadcast. Those must still settle the waiting request.
@Suite struct CorrelatedResponseRoutingTests {
    @Test func createAgentStatusResponseSettlesTheRequest() async throws {
        let (connection, transport) = try await connected()
        let sendTask = Task {
            try await connection.send(
                CreateAgentRequest(config: AgentSessionConfig(provider: "omp", cwd: "/tmp/sandbox")),
                timeout: .seconds(2))
        }
        try await waitUntil {
            outboundRequestId(ofType: "create_agent_request", in: transport) != nil
        }
        let requestId = try #require(outboundRequestId(ofType: "create_agent_request", in: transport))

        transport.push(
            text: #"{"type":"session","message":{"type":"status","payload":{"status":"agent_created","requestId":"\#(requestId)","agentId":"a1"}}}"#
        )
        let response = try await awaitValue(sendTask)
        #expect(response.status == "agent_created")
        #expect(response.agentId == "a1")
        connection.disconnect()
    }

    @Test func archiveEventResponseSettlesTheRequest() async throws {
        let (connection, transport) = try await connected()
        let sendTask = Task {
            try await connection.send(ArchiveAgentRequest(agentId: "a1"), timeout: .seconds(2))
        }
        try await waitUntil {
            outboundRequestId(ofType: "archive_agent_request", in: transport) != nil
        }
        let requestId = try #require(outboundRequestId(ofType: "archive_agent_request", in: transport))

        transport.push(
            text: #"{"type":"session","message":{"type":"agent_archived","payload":{"agentId":"a1","archivedAt":"2026-11-08T22:06:14.677Z","requestId":"\#(requestId)"}}}"#
        )
        let response = try await awaitValue(sendTask)
        #expect(response.agentId == "a1")
        connection.disconnect()
    }

    private func connected() async throws -> (DaemonConnection, FakeTransport) {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)
        return (connection, transport)
    }
}
