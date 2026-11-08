import Foundation
import PaseoProtocol

// PaseoKit: one live connection to one daemon. Knows frames, requests and reconnection.
// Knows nothing about what the app shows: no agent lists, no timelines, no UI state.
// That is PaseoStore's job.

/// Where a daemon lives and how to prove who we are.
public struct DaemonEndpoint: Sendable, Hashable {
    /// e.g. `ws://192.168.1.20:6767/ws`.
    public var url: URL
    public var credential: Credential?

    public init(url: URL, credential: Credential?) {
        self.url = url
        self.credential = credential
    }

    /// `host` may be a LAN IP, a Tailscale name, or `localhost`. Path is always `/ws`.
    public init?(host: String, port: Int = 6767, useTLS: Bool = false, credential: Credential?) {
        guard let url = URL(string: "\(useTLS ? "wss" : "ws")://\(host):\(port)/ws") else { return nil }
        self.init(url: url, credential: credential)
    }
}

public enum ConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case connected(ServerInfo)
    /// Lost the socket and retrying on its own. `attempt` starts at 1.
    case reconnecting(attempt: Int, lastError: ConnectionError)
    /// Gave up, or the daemon refused us. Only `connect()` leaves this state.
    case failed(ConnectionError)
}

public enum ConnectionError: Error, Sendable, Equatable {
    /// The daemon answered the hello with `hello.rejected` or close code 4401.
    /// `reason` is the wire reason, e.g. `password_required`, `incorrect_password`.
    case rejected(reason: String)
    case closed(code: Int, reason: String)
    case timeout
    case transport(String)
    /// A frame we could not make sense of where we needed to (e.g. a malformed response).
    case protocolViolation(String)
    /// The connection went away while a request was in flight.
    case disconnected
}

/// Things the daemon tells us without being asked.
public enum DaemonEvent: Sendable {
    case agentStream(AgentStreamPayload)
    case agentUpdate(AgentUpdate)
    /// The daemon rebuilt this agent's timeline. Drop local rows and reload the tail.
    case timelineReplacement(agentId: String, epoch: String)
    /// Any session message type this client doesn't route yet. `raw` is the whole frame.
    case unhandled(messageType: String, raw: Data)
}

/// What PaseoStore depends on. `DaemonConnection` is the real one; tests use a fake.
public protocol DaemonClient: AnyObject, Sendable {
    /// Sends a request and waits for the response with the same `requestId`. Assigns a fresh
    /// `requestId`; the caller's value is ignored. Throws `ConnectionError`.
    func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response

    /// Unsolicited daemon messages, in arrival order. Single consumer.
    var events: AsyncStream<DaemonEvent> { get }

    /// Every state change, starting with the current state. Single consumer.
    var states: AsyncStream<ConnectionState> { get }
}

extension DaemonClient {
    public func send<R: PaseoRequest>(_ request: R) async throws -> R.Response {
        try await send(request, timeout: .seconds(30))
    }
}

/// A text/binary WebSocket. `URLSessionWebSocketTransport` is the real one.
public protocol WebSocketTransport: Sendable {
    func send(text: String) async throws
    /// Suspends until the next frame. Throws when the socket closes or fails.
    func receive() async throws -> WebSocketFrame
    func close(code: Int)
}

public enum WebSocketFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// Thrown by `WebSocketTransport.receive()` when the socket closed. The daemon closes with
/// 4401 when it refuses a hello.
public struct WebSocketClosed: Error, Sendable, Equatable {
    public var code: Int
    public var reason: String
    public init(code: Int, reason: String) { self.code = code; self.reason = reason }
}

public typealias WebSocketTransportFactory = @Sendable (URL) -> any WebSocketTransport
