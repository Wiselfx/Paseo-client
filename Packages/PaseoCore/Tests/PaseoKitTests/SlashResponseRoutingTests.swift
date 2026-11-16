import Foundation
import PaseoKit
import PaseoProtocol
import Testing

/// Some RPC families use a slash-namespaced response type (`schedule/list/response`) instead of
/// the usual `_response` suffix. The connection must correlate those too, or every schedule call
/// waits for its timeout while the daemon has already answered.
@Suite struct SlashResponseRoutingTests {
    @Test func slashNamespacedResponseSettlesTheRequest() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        let sendTask = Task {
            try await connection.send(ScheduleListRequest(), timeout: .seconds(2))
        }
        try await waitUntil {
            outboundRequestId(ofType: "schedule/list", in: transport) != nil
        }
        let requestId = try #require(outboundRequestId(ofType: "schedule/list", in: transport))

        transport.push(
            text: #"{"type":"session","message":{"type":"schedule/list/response","payload":{"requestId":"\#(requestId)","schedules":[],"error":null}}}"#
        )
        let response = try await awaitValue(sendTask)
        #expect(response.error == nil)
        #expect(response.schedules.isEmpty)
        connection.disconnect()
    }
}
