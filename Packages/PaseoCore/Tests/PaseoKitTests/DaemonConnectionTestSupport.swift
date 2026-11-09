import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Synchronization
import Testing

// Test doubles and small helpers for the DaemonConnection suites.

/// A WebSocket that never touches the network: tests script the inbound frames, inspect what the
/// connection sent, and can simulate the daemon closing or failing the socket.
final class FakeTransport: WebSocketTransport, @unchecked Sendable {
    private struct State {
        var inbound: [Result<WebSocketFrame, WebSocketClosed>] = []
        var waiter: CheckedContinuation<WebSocketFrame, any Error>?
        var closedCode: Int?
        var closedReason = ""
        var outbound: [String] = []
        var outboundBinary: [Data] = []
        var outboundWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let mutex = Mutex(State())

    var outbound: [String] { mutex.withLock { $0.outbound } }
    var outboundBinary: [Data] { mutex.withLock { $0.outboundBinary } }
    var isClosedByClient: Bool { mutex.withLock { $0.closedCode != nil } }

    func send(text: String) async throws {
        let throwClosed: Int? = mutex.withLock { state in
            guard state.closedCode == nil else { return state.closedCode }
            state.outbound.append(text)
            let ready = state.outboundWaiters.filter { state.outbound.count >= $0.target }
            state.outboundWaiters.removeAll { state.outbound.count >= $0.target }
            for waiter in ready { waiter.continuation.resume() }
            return nil
        }
        if let throwClosed {
            throw WebSocketClosed(code: throwClosed, reason: "closed")
        }
    }

    func send(binary: Data) async throws {
        let throwClosed: Int? = mutex.withLock { state in
            guard state.closedCode == nil else { return state.closedCode }
            state.outboundBinary.append(binary)
            return nil
        }
        if let throwClosed {
            throw WebSocketClosed(code: throwClosed, reason: "closed")
        }
    }

    func receive() async throws -> WebSocketFrame {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = mutex.withLock { state -> Result<WebSocketFrame, WebSocketClosed>? in
                if !state.inbound.isEmpty { return state.inbound.removeFirst() }
                if let code = state.closedCode {
                    return .failure(WebSocketClosed(code: code, reason: state.closedReason))
                }
                state.waiter = continuation
                return nil
            }
            guard let immediate else { return }
            continuation.resume(with: immediate)
        }
    }

    /// Closed by `disconnect()`, not by the daemon.
    func close(code: Int) {
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            state.closedCode = code
            state.closedReason = "client closed"
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume(throwing: WebSocketClosed(code: code, reason: "client closed"))
    }

    /// A frame from the daemon.
    func push(_ frame: WebSocketFrame) {
        push(.success(frame))
    }

    func push(text: String) {
        push(.text(text))
    }

    /// The daemon goes away (or refuses us) by closing the socket.
    func serverClose(code: Int, reason: String) {
        let failure = WebSocketClosed(code: code, reason: reason)
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            state.closedCode = code
            state.closedReason = reason
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.inbound.append(.failure(failure))
            return nil
        }
        waiter?.resume(throwing: failure)
    }

    private func push(_ result: Result<WebSocketFrame, WebSocketClosed>) {
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.inbound.append(result)
            return nil
        }
        waiter?.resume(with: result)
    }
}

/// Counts transports and hands the test every instance it created.
final class FakeTransportFactory: @unchecked Sendable {
    private let mutex = Mutex<[FakeTransport]>([])
    private let urlHistory = Mutex<[URL]>([])

    var count: Int { mutex.withLock { $0.count } }
    var transports: [FakeTransport] { mutex.withLock { $0 } }
    var urls: [URL] { urlHistory.withLock { $0 } }

    func makeFactory() -> WebSocketTransportFactory {
        { [self] url in
            let transport = FakeTransport()
            mutex.withLock { $0.append(transport) }
            urlHistory.withLock { $0.append(url) }
            return transport
        }
    }
}

final class StateLog: @unchecked Sendable {
    private let mutex = Mutex<[ConnectionState]>([])

    var states: [ConnectionState] { mutex.withLock { $0 } }

    func start(_ stream: AsyncStream<ConnectionState>) -> Task<Void, Never> {
        Task { [self] in
            for await state in stream {
                mutex.withLock { $0.append(state) }
            }
        }
    }
}

final class EventLog: @unchecked Sendable {
    private let mutex = Mutex<[DaemonEvent]>([])

    var events: [DaemonEvent] { mutex.withLock { $0 } }

    func start(_ stream: AsyncStream<DaemonEvent>) -> Task<Void, Never> {
        Task { [self] in
            for await event in stream {
                mutex.withLock { $0.append(event) }
            }
        }
    }
}

struct TestTimeout: Error {}

/// Polls a lock-protected condition. Simpler and less brittle than racing continuations in tests.
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    if condition() { return }
    throw TestTimeout()
}

func testConfiguration(
    helloTimeout: Duration = .seconds(1),
    pingInterval: Duration = .seconds(10),
    idleTimeout: Duration = .seconds(10),
    reconnectBaseDelay: Duration = .milliseconds(20),
    reconnectMaxDelay: Duration = .milliseconds(80)
) -> DaemonConnection.Configuration {
    var configuration = DaemonConnection.Configuration()
    configuration.helloTimeout = helloTimeout
    configuration.pingInterval = pingInterval
    configuration.idleTimeout = idleTimeout
    configuration.reconnectBaseDelay = reconnectBaseDelay
    configuration.reconnectMaxDelay = reconnectMaxDelay
    return configuration
}

func makeConnection(
    factory: FakeTransportFactory,
    credential: Credential? = .password("secret"),
    configuration: DaemonConnection.Configuration = testConfiguration()
) -> DaemonConnection {
    let url = URL(string: "ws://127.0.0.1:6767/ws") ?? URL(fileURLWithPath: "/")
    return DaemonConnection(
        endpoint: DaemonEndpoint(url: url, credential: credential),
        clientId: "test-client",
        appVersion: "1.2.3",
        configuration: configuration,
        transportFactory: factory.makeFactory()
    )
}

func fixtureText(_ name: String) throws -> String {
    guard let text = String(data: try Fixture.data(name), encoding: .utf8) else {
        throw FixtureTextError.notUTF8(name)
    }
    return text
}

enum FixtureTextError: Error { case notUTF8(String), noMessage, notObject }

/// `requestId` is generated by the connection, so fixture responses are re-stamped before feeding
/// them back. The rest of the captured payload stays exactly as the daemon sent it.
func fixtureResponse(_ name: String, requestId: String) throws -> String {
    let data = try Fixture.data(name)
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FixtureTextError.notObject
    }
    guard var message = root["message"] as? [String: Any],
        var payload = message["payload"] as? [String: Any]
    else {
        throw FixtureTextError.noMessage
    }
    payload["requestId"] = requestId
    message["payload"] = payload
    root["message"] = message
    let rewritten = try JSONSerialization.data(withJSONObject: root)
    guard let text = String(data: rewritten, encoding: .utf8) else {
        throw FixtureTextError.notUTF8(name)
    }
    return text
}

func outboundMessage(ofType type: String, in transport: FakeTransport) -> JSONValue? {
    for frame in transport.outbound {
        guard let data = frame.data(using: .utf8),
            let object = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { continue }
        if object["message"]?["type"] == .string(type) {
            return object["message"]
        }
    }
    return nil
}

func outboundRequestId(ofType type: String, in transport: FakeTransport) -> String? {
    outboundMessage(ofType: type, in: transport)?["requestId"]?.stringValue
}

func streamEventType(_ event: AgentStreamEvent) -> String {
    switch event {
    case .turnStarted: "turn_started"
    case .turnCompleted: "turn_completed"
    case .turnFailed: "turn_failed"
    case .turnCanceled: "turn_canceled"
    case .timeline: "timeline"
    case .permissionRequested: "permission_requested"
    case .permissionResolved: "permission_resolved"
    case .attentionRequired: "attention_required"
    case .unknown(let type): type
    }
}

struct TestWaitTimeout: Error {}

/// Awaits a test task without ever blocking the suite forever. When `timeout` wins, the task is
/// cancelled and `TestWaitTimeout` is thrown, so a broken implementation fails instead of hanging.
func awaitValue<T: Sendable>(
    _ task: Task<T, any Error>, timeout: Duration = .seconds(10)
) async throws -> T {
    let (results, continuation) = AsyncStream.makeStream(
        of: Result<T, any Error>.self, bufferingPolicy: .unbounded)
    let waiter = Task {
        do {
            continuation.yield(.success(try await task.value))
        } catch {
            continuation.yield(.failure(error))
        }
        continuation.finish()
    }
    let timer = Task {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return
        }
        task.cancel()
        continuation.yield(.failure(TestWaitTimeout()))
        continuation.finish()
    }
    defer {
        waiter.cancel()
        timer.cancel()
    }
    for await result in results {
        return try result.get()
    }
    throw TestWaitTimeout()
}
