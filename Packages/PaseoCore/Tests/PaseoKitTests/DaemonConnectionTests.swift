import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@Suite struct DaemonConnectionTests {
    // MARK: 1. Success handshake

    @Test func connectReturnsServerInfoFromFixture() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let stateLog = StateLog()
        let stateTask = stateLog.start(connection.states)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)

        let hello = try JSONDecoder().decode(JSONValue.self, from: Data(try #require(transport.outbound.first).utf8))
        #expect(hello["type"] == .string("hello"))
        #expect(hello["clientId"] == .string("test-client"))
        #expect(hello["clientType"] == .string("mobile"))
        #expect(hello["auth"]?["kind"] == .string("password"))
        #expect(hello["auth"]?["password"] == .string("secret"))

        transport.push(text: try fixtureText("server_info"))
        let info = try await connectTask.value
        #expect(info.serverId == "srv_FIXTURE")
        #expect(info.protocolVersion == 1)
        #expect(stateLog.states.contains(.connected(info)))
        stateTask.cancel()
    }

    // MARK: 2. Rejection frame

    @Test func helloRejectedFailsWithoutReconnecting() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let stateLog = StateLog()
        let stateTask = stateLog.start(connection.states)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: #"{"type":"hello.rejected","reason":"incorrect_password"}"#)

        do {
            _ = try await connectTask.value
            Issue.record("connect() should have thrown")
        } catch let error as ConnectionError {
            #expect(error == .rejected(reason: "incorrect_password"))
        }

        try await waitUntil {
            stateLog.states.contains(.failed(.rejected(reason: "incorrect_password")))
        }
        // Past several reconnect delays: a rejection must never retry.
        try await Task.sleep(for: .milliseconds(150))
        #expect(factory.count == 1)
        stateTask.cancel()
    }

    // MARK: 3. 4401 close without a rejection frame

    @Test func close4401BeforeServerInfoIsARejection() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.serverClose(code: 4401, reason: "incorrect_password")

        do {
            _ = try await connectTask.value
            Issue.record("connect() should have thrown")
        } catch let error as ConnectionError {
            #expect(error == .rejected(reason: "incorrect_password"))
        }
    }

    @Test func close4401WithEmptyReasonUsesPasswordRequired() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.serverClose(code: 4401, reason: "")

        do {
            _ = try await connectTask.value
            Issue.record("connect() should have thrown")
        } catch let error as ConnectionError {
            #expect(error == .rejected(reason: "password_required"))
        }
    }

    // MARK: 4. Out-of-order responses

    @Test func responsesResolveInAnyOrder() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        _ = try await connect(connection, factory: factory)

        let agentsTask = Task {
            try await connection.send(FetchAgentsRequest(page: FetchAgentsRequest.Page(limit: 5)), timeout: .seconds(2))
        }
        let messageTask = Task {
            try await connection.send(
                SendAgentMessageRequest(agentId: "a1", text: "hello"), timeout: .seconds(2))
        }

        let transport = try #require(factory.transports.first)
        try await waitUntil { transport.outbound.count >= 3 }
        let agentsId = try #require(outboundRequestId(ofType: "fetch_agents_request", in: transport))
        let messageId = try #require(outboundRequestId(ofType: "send_agent_message_request", in: transport))

        // Reverse order: the message response arrives before the agents response.
        transport.push(text: try fixtureResponse("send_agent_message_response", requestId: messageId))
        transport.push(text: try fixtureResponse("fetch_agents_response", requestId: agentsId))

        let agents = try await agentsTask.value
        let message = try await messageTask.value
        #expect(agents.entries.first?.agent.provider == "opencode")
        #expect(message.accepted)
        #expect(message.agentId == "1c51ee58-765c-4f8d-bf27-7009338b361e")
    }

    // MARK: 5. Timeout drops the late response

    @Test func timeoutForgetsTheRequestAndDropsALateResponse() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        _ = try await connect(connection, factory: factory)
        let eventLog = EventLog()
        let eventTask = eventLog.start(connection.events)

        let transport = try #require(factory.transports.first)
        let sendTask = Task {
            try await connection.send(
                SendAgentMessageRequest(agentId: "a1", text: "slow"), timeout: .milliseconds(50))
        }
        try await waitUntil { outboundRequestId(ofType: "send_agent_message_request", in: transport) != nil }
        let requestId = try #require(outboundRequestId(ofType: "send_agent_message_request", in: transport))

        do {
            _ = try await sendTask.value
            Issue.record("send() should have timed out")
        } catch let error as ConnectionError {
            #expect(error == .timeout)
        }

        transport.push(text: try fixtureResponse("send_agent_message_response", requestId: requestId))
        try await Task.sleep(for: .milliseconds(120))
        #expect(eventLog.events.isEmpty)
        eventTask.cancel()
    }

    // MARK: 6. Event routing

    @Test func streamFramesArriveAsAgentStreamEventsInOrder() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        _ = try await connect(connection, factory: factory)
        let eventLog = EventLog()
        let eventTask = eventLog.start(connection.events)
        let transport = try #require(factory.transports.first)

        let frames = try Fixture.streamFrames()
        let expectedSeqs = try frames.map { data in
            try JSONDecoder().decode(SessionPayloadEnvelope<AgentStreamPayload>.self, from: data).payload.seq
        }
        for data in frames {
            transport.push(text: try #require(String(data: data, encoding: .utf8)))
        }

        try await waitUntil { eventLog.events.count == frames.count }
        let recorded = eventLog.events
        for (index, event) in recorded.enumerated() {
            guard case .agentStream(let payload) = event else {
                Issue.record("event \(index) was not agentStream")
                continue
            }
            #expect(payload.seq == expectedSeqs[index])
        }

        transport.push(text: #"{"type":"session","message":{"type":"future_magic","payload":{"x":1}}}"#)
        try await waitUntil { eventLog.events.count == frames.count + 1 }
        guard case .unhandled(let messageType, let raw) = eventLog.events.last else {
            Issue.record("expected an unhandled event")
            eventTask.cancel()
            return
        }
        #expect(messageType == "future_magic")
        #expect(String(data: raw, encoding: .utf8)?.contains("future_magic") == true)
        eventTask.cancel()
    }

    // MARK: 7. Reconnect after a connected socket dies

    @Test func connectedSocketDeathReconnectsAndResetsState() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let stateLog = StateLog()
        let stateTask = stateLog.start(connection.states)

        let (first, info) = try await connect(connection, factory: factory)
        #expect(info.serverId == "srv_FIXTURE")

        let sendTask = Task {
            try await connection.send(
                SendAgentMessageRequest(agentId: "a1", text: "in flight"), timeout: .seconds(3))
        }
        try await waitUntil { outboundRequestId(ofType: "send_agent_message_request", in: first) != nil }

        first.serverClose(code: 1006, reason: "gone")

        do {
            _ = try await sendTask.value
            Issue.record("pending request should have failed")
        } catch let error as ConnectionError {
            #expect(error == .disconnected)
        }

        try await waitUntil { factory.count == 2 }
        let second = try #require(factory.transports.last)
        try await waitUntil { second.outbound.count >= 1 }
        second.push(text: try fixtureText("server_info"))

        try await waitUntil {
            var sawReconnect = false
            for state in stateLog.states {
                if case .reconnecting(let attempt, _) = state, attempt == 1 { sawReconnect = true }
                if case .connected = state, sawReconnect { return true }
            }
            return false
        }
        #expect(factory.count == 2)
        stateTask.cancel()
    }

    // MARK: 8. disconnect()

    @Test func disconnectFailsPendingRequestsAndStopsReconnecting() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let stateLog = StateLog()
        let stateTask = stateLog.start(connection.states)

        _ = try await connect(connection, factory: factory)
        let transport = try #require(factory.transports.first)

        let sendTask = Task {
            try await connection.send(
                SendAgentMessageRequest(agentId: "a1", text: "pending"), timeout: .seconds(3))
        }
        try await waitUntil { outboundRequestId(ofType: "send_agent_message_request", in: transport) != nil }

        connection.disconnect()

        do {
            _ = try await sendTask.value
            Issue.record("pending request should have failed")
        } catch let error as ConnectionError {
            #expect(error == .disconnected)
        }

        try await waitUntil { stateLog.states.last == .idle }
        #expect(transport.isClosedByClient)
        try await Task.sleep(for: .milliseconds(150))
        #expect(factory.count == 1)
        stateTask.cancel()
    }

    // MARK: Helpers

    /// Connects and feeds the fixture `server_info`.
    private func connect(
        _ connection: DaemonConnection, factory: FakeTransportFactory
    ) async throws -> (FakeTransport, ServerInfo) {
        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        let info = try await connectTask.value
        return (transport, info)
    }
}
