import Foundation
import PaseoProtocol

// PaseoKit: one live connection to one daemon. Knows frames, requests and reconnection.
// Knows nothing about what the app shows: no agent lists, no timelines, no UI state.
// That is PaseoStore's job.

/// Where a daemon lives and how to prove who we are.
public struct DaemonEndpoint: Sendable, Hashable {
    /// e.g. `ws://192.168.1.20:6767/ws`, or the relay's `wss://…/ws?serverId=…&role=client&v=2`.
    public var url: URL
    public var credential: Credential?
    /// Non-nil when `url` is the relay: the socket is wrapped in a Noise channel and nothing —
    /// credentials included — is readable on the wire before that channel opens.
    public var relay: RelayLink?

    public init(url: URL, credential: Credential?, relay: RelayLink? = nil) {
        self.url = url
        self.credential = credential
        self.relay = relay
    }

    /// `host` may be a LAN IP, a Tailscale name, or `localhost`. Path is always `/ws`.
    public init?(host: String, port: Int = 6767, useTLS: Bool = false, credential: Credential?) {
        guard let url = URL(string: "\(useTLS ? "wss" : "ws")://\(host):\(port)/ws") else { return nil }
        self.init(url: url, credential: credential)
    }

    /// Everything a relay socket needs that a direct socket does not.
    ///
    /// The daemon public key is the trust anchor: it authenticated the pairing offer and it
    /// authenticates the Noise handshake, so it must travel with the endpoint, not with a global.
    public struct RelayLink: Sendable, Hashable {
        /// Stable daemon identity and relay session id, e.g. `srv_…`.
        public var serverID: String
        public var daemonPublicKeyB64: String
        /// 32-byte X25519 key decoded from `daemonPublicKeyB64`.
        public var daemonPublicKey: [UInt8]
        /// Floor this connection must meet. Only `protected` exists, so this is a constant with
        /// a name: the store may raise it, nothing can lower it.
        public var minimumSecurityMode: ConnectionOffer.Security

        public init(
            serverID: String, daemonPublicKeyB64: String, daemonPublicKey: [UInt8],
            minimumSecurityMode: ConnectionOffer.Security = .protected
        ) {
            self.serverID = serverID
            self.daemonPublicKeyB64 = daemonPublicKeyB64
            self.daemonPublicKey = daemonPublicKey
            self.minimumSecurityMode = minimumSecurityMode
        }

        /// The relay link described by a validated pairing offer.
        public init(offer: ConnectionOffer, minimumSecurityMode: ConnectionOffer.Security? = nil) {
            self.init(
                serverID: offer.serverID,
                daemonPublicKeyB64: offer.daemonPublicKeyB64,
                daemonPublicKey: offer.daemonPublicKey,
                minimumSecurityMode: minimumSecurityMode ?? offer.minimumSecurityMode ?? .protected)
        }
    }

    /// A relay endpoint for this offer. `url` is the relay WebSocket, so `credential` must be the
    /// offer's daemon password — it rides inside the encrypted hello.
    public init(offer: ConnectionOffer, credential: Credential?) throws {
        self.init(
            url: try offer.relayWebSocketURL(), credential: credential,
            relay: RelayLink(offer: offer))
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

public enum ConnectionError: Error, Sendable, Equatable, LocalizedError {
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

extension ConnectionError {
    /// True when a request may have been applied although its answer never arrived, so a mutation
    /// must be inspected before it is retried. Upstream: public-docs/sdk/reference.md:259-262
    /// (`DAEMON_CONNECTION_LOST`, `outcome: "unknown"`: "Inspect before retrying a mutation.").
    /// `.disconnected` can also mean nothing was written (`DaemonConnection.send` guard), so this
    /// over-reports there; the enum cannot tell the two apart.
    public var outcomeUnknown: Bool {
        switch self {
        case .disconnected, .timeout, .closed, .transport: true
        case .rejected, .protocolViolation: false
        }
    }

    /// One plain sentence per case. Wording is copied from the app's `AppModel.describe(_:)`
    /// (App/Sources/AppModel.swift:388-405) so the sheet and the banner say the same thing.
    public var errorDescription: String? {
        switch self {
        case .rejected(let reason):
            switch reason {
            case "password_required": return "This host needs a password."
            case "incorrect_password": return "Wrong password."
            case "incompatible_protocol": return "This host's version isn't compatible. Update Paseo."
            default: return "The host refused the connection (\(reason))."
            }
        case .timeout:
            return "The host didn't answer. Check the address and that it's running."
        case .transport(let message):
            return "Couldn't reach the host: \(message)"
        case .closed(let code, let reason):
            switch code {
            case 4002:
                // Terminal (R17): protected handshake failed — relinking the same way will fail again.
                return "The pairing link didn't work. Ask the host to show a new pairing code."
            case 4003:
                return "The encrypted connection failed. Check the pairing link and try again."
            default:
                return "Connection closed (\(code)) \(reason)"
            }
        case .protocolViolation(let message):
            return "Unexpected reply from the host: \(message)"
        case .disconnected:
            return "Disconnected."
        }
    }
}

/// Things the daemon tells us without being asked.
public enum DaemonEvent: Sendable {
    case agentStream(AgentStreamPayload)
    case agentUpdate(AgentUpdate)
    /// The daemon rebuilt this agent's timeline. Drop local rows and reload the tail.
    case timelineReplacement(agentId: String, epoch: String)
    /// Any session message type this client doesn't route yet. `raw` is the whole frame.
    case unhandled(messageType: String, raw: Data)
    /// A WebSocket binary frame, unparsed. Terminal streams ride here; the store decodes them.
    case binaryFrame(Data)
}

/// What PaseoStore depends on. `DaemonConnection` is the real one; tests use a fake.
public protocol DaemonClient: AnyObject, Sendable {
    /// Sends a request and waits for the response with the same `requestId`. Assigns a fresh
    /// `requestId` (unless one was pre-set on the request); throws `ConnectionError`.
    func send<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> R.Response

    /// Sends a request and returns as soon as its frame has been written to the socket —
    /// without awaiting the response. Multi-phase flows (file upload) initiate, stream their
    /// correlated binary frames in order, then await the response.
    func initiate<R: PaseoRequest>(_ request: R, timeout: Duration) async throws -> InitiatedResponse<R>

    /// Sends a session message with no correlated response (`terminal_input`,
    /// `subscribe_terminals_request`, `unsubscribe_terminal_request`). Throws `ConnectionError`.
    func send<M: PaseoOutboundMessage>(_ message: M) async throws

    /// Sends a raw binary WebSocket frame, unparsed — `FileBegin`/`FileChunk`/`FileEnd` frames
    /// for file upload ride here, correlated by `requestId`. Throws `ConnectionError`.
    func send(binary: Data) async throws

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

/// A request whose frame has been written but whose response has not arrived yet.
/// `value()` suspends until the daemon answers; throws `ConnectionError`.
public struct InitiatedResponse<R: PaseoRequest>: Sendable {
    /// The id the daemon will correlate its response to.
    public let requestId: String
    private let perform: @Sendable () async throws -> R.Response

    public init(requestId: String, perform: @escaping @Sendable () async throws -> R.Response) {
        self.requestId = requestId
        self.perform = perform
    }

    public func value() async throws -> R.Response {
        try await perform()
    }
}

/// A transport that can say which endpoint security it actually established.
///
/// `DaemonConnection` uses this after `server_info` to refuse a relay session that was somehow not
/// protected. A direct socket has nothing to report and does not conform.
public protocol RelaySecurityReporting: Sendable {
    /// `.protected` once the Noise channel is open; nil while handshaking, on a direct socket, or
    /// after the channel closed.
    var negotiatedRelaySecurity: ConnectionOffer.Security? { get }
}

/// A text/binary WebSocket. `URLSessionWebSocketTransport` is the real one.
public protocol WebSocketTransport: Sendable {
    func send(text: String) async throws
    /// Sends a raw binary frame. File-upload frames ride here.
    func send(binary: Data) async throws
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

/// Builds the socket for one endpoint. A relay endpoint needs the offer material, so the factory
/// takes the whole endpoint rather than a bare URL.
public typealias WebSocketTransportFactory = @Sendable (DaemonEndpoint) -> any WebSocketTransport
