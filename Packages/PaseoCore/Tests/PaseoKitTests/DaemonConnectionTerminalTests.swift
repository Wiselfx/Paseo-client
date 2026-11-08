import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@Suite struct DaemonConnectionTerminalTests {
    @Test func helloAdvertisesOnlyImplementedTerminalCapabilities() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        let hello = try JSONDecoder().decode(
            JSONValue.self, from: Data(try #require(transport.outbound.first).utf8))

        #expect(hello["capabilities"]?["hello_rejection"] == .bool(true))
        #expect(hello["capabilities"]?["terminal_chunked_replay"] == .bool(true))
        // We do not pace chunked sends and detach through the legacy terminal unsubscribe.
        #expect(hello["capabilities"]?["binary_chunking_v1"] == nil)
        #expect(hello["capabilities"]?["owned_subscriptions"] == nil)

        transport.push(text: try fixtureText("server_info"))
        _ = try await connectTask.value
    }

    @Test func binaryFramesArriveAsGenericBinaryEvents() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)
        let log = EventLog()
        let task = log.start(connection.events)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await connectTask.value

        let frame = TerminalStreamFrame(
            opcode: .output, slot: 3, payload: Data("hello".utf8)
        ).encoded
        transport.push(.binary(frame))

        try await waitUntil {
            log.events.contains {
                if case .binaryFrame = $0 { return true }
                return false
            }
        }
        guard case .binaryFrame(let data) = log.events.last else {
            Issue.record("expected a binary frame event")
            task.cancel()
            return
        }
        #expect(data == frame)
        task.cancel()
    }

    @Test func outboundTerminalInputIsFireAndForget() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await connectTask.value

        try await connection.send(TerminalInput.input("ls\r", terminalId: "t1"))
        try await waitUntil {
            outboundMessage(ofType: "terminal_input", in: transport) != nil
        }
        let message = try #require(outboundMessage(ofType: "terminal_input", in: transport))
        #expect(message["terminalId"] == .string("t1"))
        #expect(message["message"]?["type"] == .string("input"))
        #expect(message["message"]?["data"] == .string("ls\r"))
        #expect(message["requestId"] == nil)
    }
}
