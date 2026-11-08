import Foundation
import PaseoProtocol

/// The real `DaemonClient`: one WebSocket to one daemon, with hello, request/response matching,
/// unsolicited-event routing, keepalive and automatic reconnection.
///
/// IMPLEMENTATION TICKET: docs/tickets/T1-daemon-connection.md
public final class DaemonConnection: DaemonClient, @unchecked Sendable {
    public let endpoint: DaemonEndpoint
    public let clientId: String
    public let appVersion: String?
    public let configuration: Configuration

    /// Timings. Defaults suit a phone; tests pass small values.
    public struct Configuration: Sendable {
        /// How long `connect()` waits for `server_info` after sending hello.
        public var helloTimeout: Duration = .seconds(15)
        /// How often to send `{"type":"ping"}` while connected.
        public var pingInterval: Duration = .seconds(20)
        /// No frame at all for this long means the socket is dead: reconnect.
        public var idleTimeout: Duration = .seconds(45)
        /// Delay before reconnect attempt n is `min(base * 2^(n-1), max)` plus up to 20% jitter.
        public var reconnectBaseDelay: Duration = .milliseconds(500)
        public var reconnectMaxDelay: Duration = .seconds(15)
        public init() {}
    }

    /// - Parameters:
    ///   - clientId: stable per install. The daemon uses it for presence and notifications.
    ///   - transportFactory: injected so tests can run without a network.
    public init(
        endpoint: DaemonEndpoint,
        clientId: String,
        appVersion: String?,
        configuration: Configuration = Configuration(),
        transportFactory: @escaping WebSocketTransportFactory = { URLSessionWebSocketTransport(url: $0) }
    ) {
        self.endpoint = endpoint
        self.clientId = clientId
        self.appVersion = appVersion
        self.configuration = configuration
        fatalError("T1: not implemented")
    }

    /// Opens the socket, sends `Hello`, and returns once `server_info` arrives.
    /// Throws `ConnectionError.rejected` without retrying when the daemon refuses the hello.
    /// After success, a dropped socket reconnects by itself until `disconnect()`.
    @discardableResult
    public func connect() async throws -> ServerInfo { fatalError("T1: not implemented") }

    /// Closes for good. In-flight requests fail with `.disconnected`. State becomes `.idle`.
    public func disconnect() { fatalError("T1: not implemented") }

    public func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response {
        fatalError("T1: not implemented")
    }

    public var events: AsyncStream<DaemonEvent> { fatalError("T1: not implemented") }
    public var states: AsyncStream<ConnectionState> { fatalError("T1: not implemented") }
}

/// `URLSessionWebSocketTask` behind `WebSocketTransport`. Works on Apple platforms and Linux.
///
/// IMPLEMENTATION TICKET: docs/tickets/T1-daemon-connection.md
public final class URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    public init(url: URL) { fatalError("T1: not implemented") }
    public func send(text: String) async throws { fatalError("T1: not implemented") }
    public func receive() async throws -> WebSocketFrame { fatalError("T1: not implemented") }
    public func close(code: Int) { fatalError("T1: not implemented") }
}
