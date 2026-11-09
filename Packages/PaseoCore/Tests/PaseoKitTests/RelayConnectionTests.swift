import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Synchronization
import Testing

/// R17: `DaemonConnection` over the relay. The relay socket is real Noise traffic against
/// `FakeRelaySocket`; what these tests pin down is the state machine above it — the downgrade
/// check, terminal close codes and "no silent reconnect loops".
@Suite struct RelayConnectionTests {
    static let serverInfoJSON = #"""
        {"type":"session","message":{"type":"status","payload":{"status":"server_info",
        "serverId":"srv_FIXTURE","protocolVersion":1,"features":{"relayProtectedSecurity":true}}}}
        """#

    static let serverID = "srv_AAAAAAAAAAAA"

    /// Everything one relay connection needs: an endpoint, a factory that records its sockets, and
    /// the peer that answers the handshake.
    struct Harness {
        var connection: DaemonConnection
        var factory: FakeRelayFactory
        var peer: RelayDaemonPeer
        var stateLog: StateLog

        var socket: FakeRelaySocket {
            get throws { try #require(factory.sockets.last) }
        }

        func waitConnected() async throws -> ServerInfo {
            let connectTask = Task { try await connection.connect() }
            let socket = try await Self.awaitSocket(factory)
            // Wait for the app hello to reach the fake daemon, not just for its side of the
            // handshake to finish. `peer.isOpen` is set when the daemon *builds* its ready, one
            // step before the client receives it (`RelayResponderFake.swift:183` vs `:200`), so a
            // frame pushed on that signal can arrive while the client transport is still
            // handshaking, where it is dropped as pre-open noise (`RelayTransport.swift:390`).
            // A real daemon answers the hello with server_info; this is that order.
            try await waitUntil {
                socket.peer.receivedTexts.contains { $0.contains(#""type":"hello""#) }
            }
            socket.pushDaemonText(RelayConnectionTests.serverInfoJSON)
            return try await awaitValue(connectTask)
        }

        static func awaitSocket(_ factory: FakeRelayFactory) async throws -> FakeRelaySocket {
            try await waitUntil { factory.sockets.contains { $0.peer.isOpen } }
            return try #require(factory.sockets.last)
        }
    }

    static func makeHarness(
        peers: [RelayDaemonPeer] = [RelayDaemonPeer()],
        password: String? = "hunter2",
        transportFactory: WebSocketTransportFactory? = nil
    ) throws -> Harness {
        let factory = FakeRelayFactory(peers: peers)
        let peer = peers[0]
        let credential = password.map { Credential.password($0) }
        let url = try #require(
            URL(string: "wss://relay.example.test/ws?serverId=\(serverID)&role=client&v=2"))
        let endpoint = DaemonEndpoint(
            url: url, credential: credential,
            relay: DaemonEndpoint.RelayLink(
                serverID: serverID, daemonPublicKeyB64: peer.publicKeyB64,
                daemonPublicKey: peer.staticKey.publicKey))
        let connection = DaemonConnection(
            endpoint: endpoint, clientId: "test-client", appVersion: "1.2.3",
            configuration: testConfiguration(helloTimeout: .seconds(5)),
            transportFactory: transportFactory ?? factory.makeFactory())
        let stateLog = StateLog()
        _ = stateLog.start(connection.states)
        return Harness(connection: connection, factory: factory, peer: peer, stateLog: stateLog)
    }

    // MARK: Happy path

    @Test func aRelaySessionConnectsAndTheRelaySeesNoPlaintext() async throws {
        let harness = try Self.makeHarness()
        let info = try await harness.waitConnected()
        #expect(info.serverId == "srv_FIXTURE")
        #expect(harness.connection.endpoint.relay?.serverID == Self.serverID)

        // The daemon received the ordinary hello, decrypted, with the password inside it.
        try await waitUntil {
            harness.peer.receivedTexts.contains { $0.contains(#""type":"hello""#) }
        }
        let hello = try #require(harness.peer.receivedTexts.first { $0.contains(#""type":"hello""#) })
        #expect(hello.contains(#""password":"hunter2""#))
        #expect(hello.contains(#""owned_subscriptions":true"#))

        // Nothing the client wrote to the relay socket is plaintext: only the E2EE hello and
        // base64 records.
        for frame in try harness.socket.sent {
            if case .text(let text) = frame {
                #expect(!text.contains("hunter2"))
                #expect(!text.contains(#""type":"hello""#))
                #expect(text.hasPrefix("{") ? text.contains("e2ee_hello") : Data(base64Encoded: text) != nil)
            }
        }
        // The state log drains in its own task, so an awaited `connect()` does not order the
        // append: await the entry, do not read it.
        try await waitForLoggedState(.connected(info), in: harness.stateLog)
        harness.connection.disconnect()
    }

    @Test func theHandshakeHappensBeforeTheHelloIsWritten() async throws {
        let harness = try Self.makeHarness()
        _ = try await harness.waitConnected()
        // The first text frame is the E2EE hello; the app hello comes after the channel opened.
        let texts = try harness.socket.sent.compactMap { frame -> String? in
            if case .text(let text) = frame { return text }
            return nil
        }
        #expect(texts.first?.contains("e2ee_hello") == true)
        #expect(texts.dropFirst().allSatisfy { !$0.contains("e2ee_hello") })
        harness.connection.disconnect()
    }

    // MARK: Downgrade check

    @Test func aRelaySessionWithoutProtectedSecurityIsRefusedWith4002() async throws {
        // A transport that is not a relay channel at all: it reports no negotiated security, so
        // the session must be refused even though `server_info` arrives and the daemon advertises
        // protected support.
        let factory = FakeTransportFactory()
        let connection = DaemonConnection(
            endpoint: DaemonEndpoint(
                url: URL(string: "ws://127.0.0.1:6767/ws") ?? URL(fileURLWithPath: "/"),
                credential: .password("hunter2"),
                relay: DaemonEndpoint.RelayLink(
                    serverID: Self.serverID, daemonPublicKeyB64: "k",
                    daemonPublicKey: [UInt8](repeating: 7, count: 32))),
            clientId: "test-client", appVersion: "1.2.3",
            configuration: testConfiguration(), transportFactory: factory.makeFactory())
        let stateLog = StateLog()
        let stateTask = stateLog.start(connection.states)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: Self.serverInfoJSON)

        let error = await Self.error { try await awaitValue(connectTask) }
        guard case .closed(let code, let reason)? = error as? ConnectionError else {
            Issue.record("expected a 4002 close, got \(String(describing: error))")
            stateTask.cancel()
            return
        }
        #expect(code == 4002)
        #expect(reason == "daemon requires protected endpoint security but the relay channel is not protected")
        try await waitUntil { stateLog.states.contains(.failed(.closed(code: code, reason: reason))) }
        #expect(transport.isClosedByClient)
        stateTask.cancel()
    }

    @Test func aRelaySessionIsRefusedEvenWithoutTheDaemonFeatureFlag() async throws {
        // Same, but the daemon does not advertise `relayProtectedSecurity`: still refused, because
        // a relay session is never admitted unprotected.
        let factory = FakeTransportFactory()
        let connection = DaemonConnection(
            endpoint: DaemonEndpoint(
                url: URL(string: "ws://127.0.0.1:6767/ws") ?? URL(fileURLWithPath: "/"),
                credential: nil,
                relay: DaemonEndpoint.RelayLink(
                    serverID: Self.serverID, daemonPublicKeyB64: "k",
                    daemonPublicKey: [UInt8](repeating: 7, count: 32))),
            clientId: "test-client", appVersion: "1.2.3",
            configuration: testConfiguration(), transportFactory: factory.makeFactory())

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(
            text: #"{"type":"session","message":{"type":"status","payload":{"status":"server_info","serverId":"srv_FIXTURE"}}}"#)

        let error = await Self.error { try await awaitValue(connectTask) }
        guard case .closed(let code, let reason)? = error as? ConnectionError else {
            Issue.record("expected a 4002 close, got \(String(describing: error))")
            return
        }
        #expect(code == 4002)
        #expect(reason == "relay channel is not protected")
    }

    // MARK: Terminal close codes

    @Test func a4003RecordFailureFailsTheSessionWithoutReconnecting() async throws {
        let harness = try Self.makeHarness()
        _ = try await harness.waitConnected()

        try harness.socket.serverClose(code: 4003, reason: "inbound record failed")
        try await waitUntil {
            harness.stateLog.states.contains(
                .failed(.closed(code: 4003, reason: "inbound record failed")))
        }
        // Past several reconnect delays: 4003 is terminal.
        try await Task.sleep(for: .milliseconds(150))
        #expect(harness.factory.count == 1)
        #expect(!harness.stateLog.states.contains { state in
            if case .reconnecting = state { return true }
            return false
        })
    }

    @Test func a4002HandshakeFailureOnReconnectStopsTheLoop() async throws {
        // The first socket answers protected; the second daemon offers only legacy (an old daemon
        // behind the same identity). That is the "cannot establish protection" case: fail instead
        // of retrying forever.
        let harness = try Self.makeHarness(
            peers: [RelayDaemonPeer(), RelayDaemonPeer(behaviour: .legacyOnly)])
        _ = try await harness.waitConnected()

        try harness.socket.serverClose(code: 1006, reason: "network")
        try await waitUntil(timeout: .seconds(5)) {
            harness.stateLog.states.contains { state in
                if case .failed(.closed(code: 4002, _)) = state { return true }
                return false
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(harness.factory.count == 2)
    }

    @Test func aRelayFlapReconnectsLikeAnyOtherSocket() async throws {
        // Same daemon key after the flap: the reconnect is an ordinary new protected handshake.
        let key = NoiseKeyPair.random()
        let harness = try Self.makeHarness(
            peers: [RelayDaemonPeer(staticKey: key), RelayDaemonPeer(staticKey: key)])
        _ = try await harness.waitConnected()

        try harness.socket.serverClose(code: 1006, reason: "relay restart")
        try await waitUntil(timeout: .seconds(5)) { harness.factory.count == 2 }
        let second = try #require(harness.factory.sockets.last)
        try await waitUntil { second.peer.isOpen }
        // Same gate as `waitConnected`: `isOpen` is one step ahead of the ready reaching the client.
        try await waitUntil {
            second.peer.receivedTexts.contains { $0.contains(#""type":"hello""#) }
        }
        second.pushDaemonText(Self.serverInfoJSON)
        try await waitUntil(timeout: .seconds(5)) {
            harness.stateLog.states.contains { state in
                if case .connected = state { return true }
                return false
            }
        }
        harness.connection.disconnect()
    }

    // MARK: Protocol unchanged over the relay

    @Test func requestsAndEventsRoundTripThroughTheRelay() async throws {
        let harness = try Self.makeHarness()
        _ = try await harness.waitConnected()
        let socket = try harness.socket
        let events = EventLog()
        let eventTask = events.start(harness.connection.events)

        let sendTask = Task {
            try await harness.connection.send(
                ProviderDiagnosticRequest(provider: "omp"), timeout: .seconds(5))
        }
        try await waitUntil {
            socket.peer.receivedTexts.contains { $0.contains("provider_diagnostic_request") }
        }
        let request = try #require(
            socket.peer.receivedTexts.first { $0.contains("provider_diagnostic_request") })
        let requestId = try #require(
            try JSONDecoder().decode(JSONValue.self, from: Data(request.utf8))["message"]?["requestId"]?
                .stringValue)

        socket.pushDaemonText(
            #"{"type":"session","message":{"type":"provider_diagnostic_response","requestId":"\#(requestId)","payload":{"requestId":"\#(requestId)","provider":"omp","diagnostic":"ok"}}}"#
        )
        let response = try await awaitValue(sendTask)
        #expect(response.diagnostic == "ok")

        // An unsolicited event rides the same channel, unchanged.
        socket.pushDaemonText(
            #"{"type":"session","message":{"type":"agent_update","payload":{"kind":"remove","agentId":"a1"}}}"#)
        try await waitUntil { !events.events.isEmpty }
        guard case .agentUpdate(.remove(let agentId)) = try #require(events.events.first) else {
            Issue.record("expected an agent_update, got \(String(describing: events.events.first))")
            eventTask.cancel()
            harness.connection.disconnect()
            return
        }
        #expect(agentId == "a1")
        eventTask.cancel()
        harness.connection.disconnect()
    }

    @Test func binaryFramesCrossTheRelayUnchanged() async throws {
        let harness = try Self.makeHarness()
        _ = try await harness.waitConnected()
        let socket = try harness.socket
        let events = EventLog()
        let eventTask = events.start(harness.connection.events)

        let payload = Data((0..<256).map { UInt8($0) })
        socket.pushDaemonBinary(payload)
        try await waitUntil { !events.events.isEmpty }
        guard case .binaryFrame(let received) = try #require(events.events.first) else {
            Issue.record("expected a binary frame")
            eventTask.cancel()
            harness.connection.disconnect()
            return
        }
        #expect(received == payload)
        eventTask.cancel()
        harness.connection.disconnect()
    }

    // MARK: Helpers

    static func error<T>(_ operation: () async throws -> T) async -> (any Error)? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }
}
