import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

/// P5-A: both connection streams are bounded. A consumer that lags drops the oldest events
/// instead of letting the buffer grow without limit and catching up in a burst.
@Suite struct DaemonConnectionBackpressureTests {
    @Test func theEventStreamKeepsOnlyTheNewestEvents() async throws {
        let factory = FakeTransportFactory()
        let connection = makeConnection(factory: factory)

        let connectTask = Task { try await connection.connect() }
        try await waitUntil { factory.count == 1 && factory.transports[0].outbound.count >= 1 }
        let transport = try #require(factory.transports.first)
        transport.push(text: try fixtureText("server_info"))
        _ = try await awaitValue(connectTask)

        // Push more frames than the buffer holds, with no consumer attached. The receive loop
        // drains the transport into the bounded buffer, dropping the oldest.
        let total = 200
        for index in 0..<total {
            transport.push(
                text: #"{"type":"session","message":{"type":"future_magic","payload":{"x":\#(index)}}}"#
            )
        }
        try await Task.sleep(for: .milliseconds(500))

        var iterator = connection.events.makeAsyncIterator()
        var received: [Int] = []
        for _ in 0..<64 {
            guard let event = await iterator.next() else { break }
            guard case .unhandled(_, let raw) = event else { continue }
            let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
            let message = object?["message"] as? [String: Any]
            let payload = message?["payload"] as? [String: Any]
            if let x = payload?["x"] as? Int { received.append(x) }
        }

        #expect(received.count == 64)
        #expect(received.first == total - 64, "the oldest events were dropped")
        #expect(received.last == total - 1)
    }
}
