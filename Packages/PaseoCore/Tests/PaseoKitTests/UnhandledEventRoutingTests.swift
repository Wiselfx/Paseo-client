import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

/// Events whose payload happens to carry a `requestId` must still reach stores as `.unhandled`.
/// `checkout_status_update` carries `requestId: "subscription:<cwd>"` from the daemon's git
/// observer; treating that as a response would silently drop every live status.
@Suite struct UnhandledEventRoutingTests {
    @Test func checkoutStatusUpdateWithPayloadRequestIdIsUnhandled() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        let eventLog = EventLog()
        let eventTask = eventLog.start(connection.events)

        let data = try Fixture.data("checkout_status_update_00", in: "workspaces")
        let text = try #require(String(data: data, encoding: .utf8))
        transport.push(text: text)

        try await waitUntil { eventLog.events.count == 1 }
        guard case .unhandled(let messageType, let raw) = try #require(eventLog.events.first) else {
            Issue.record("expected an unhandled event")
            eventTask.cancel()
            return
        }
        #expect(messageType == "checkout_status_update")
        #expect(raw == data)
        eventTask.cancel()
        connection.disconnect()
    }

    @Test func unknownResponseTypeDoesNotSettleAPendingRequest() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        let eventLog = EventLog()
        let eventTask = eventLog.start(connection.events)

        // A frame with a requestId but an event type must not resolve anything; it is an event.
        let frame = #"{"type":"session","message":{"type":"future_event","payload":{"requestId":"nope","x":1}}}"#
        transport.push(text: frame)
        try await waitUntil { eventLog.events.count == 1 }
        guard case .unhandled(let messageType, _) = try #require(eventLog.events.first) else {
            Issue.record("expected an unhandled event")
            eventTask.cancel()
            return
        }
        #expect(messageType == "future_event")
        eventTask.cancel()
        connection.disconnect()
    }
}
