import Foundation

// Wire framing. Every application message travels as
//   client -> daemon: {"type":"session","message":{"type":"<x>_request","requestId":…,…}}
//   daemon -> client: {"type":"session","message":{"type":"<x>_response","payload":{"requestId":…,…}}}
// WebSocket-level messages (hello, ping/pong, hello.rejected) are not wrapped.
// Source: packages/protocol/src/messages.ts, "WebSocket Level Messages".

/// A request this client can send. Conformers declare their wire names and response payload.
/// Fields are encoded flat next to `type` inside `message`.
public protocol PaseoRequest: Encodable, Sendable {
    associatedtype Response: Decodable & Sendable
    /// `message.type` of the request, e.g. `fetch_agents_request`.
    static var type: String { get }
    /// `message.type` of the matching response, e.g. `fetch_agents_response`.
    static var responseType: String { get }
    var requestId: String { get set }
}

/// Encodes `{"type":"session","message":{"type":R.type, …request fields}}`.
public struct SessionRequestEnvelope<R: PaseoRequest>: Encodable {
    public let request: R
    public init(_ request: R) { self.request = request }

    private struct Message: Encodable {
        let request: R
        func encode(to encoder: Encoder) throws {
            try request.encode(to: encoder)
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(R.type, forKey: AnyKey("type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode("session", forKey: AnyKey("type"))
        try c.encode(Message(request: request), forKey: AnyKey("message"))
    }
}

/// Decodes the `payload` of a session message: `{"type":"session","message":{"payload":P}}`.
public struct SessionPayloadEnvelope<P: Decodable & Sendable>: Decodable, Sendable {
    public let messageType: String
    public let payload: P

    private enum Outer: String, CodingKey { case message }
    private enum Inner: String, CodingKey { case type, payload }

    public init(from decoder: Decoder) throws {
        let inner = try decoder.container(keyedBy: Outer.self).nestedContainer(keyedBy: Inner.self, forKey: .message)
        messageType = try inner.decode(String.self, forKey: .type)
        payload = try inner.decode(P.self, forKey: .payload)
    }
}

/// The cheap first pass over every inbound frame: enough to route it without decoding it fully.
public struct InboundHeader: Decodable, Sendable, Equatable {
    /// Outer type: `session`, `pong`, or `hello.rejected`.
    public let type: String
    /// `message.type` for session messages, e.g. `agent_stream` or `fetch_agents_response`.
    public let messageType: String?
    /// `message.payload.requestId`, present on responses.
    public let requestId: String?
    /// `message.payload.status`, present on `status` messages such as `server_info`.
    public let status: String?

    private enum Outer: String, CodingKey { case type, message }
    private enum Inner: String, CodingKey { case type, payload }
    private enum Payload: String, CodingKey { case requestId, status }

    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        type = try outer.decode(String.self, forKey: .type)
        guard let inner = try? outer.nestedContainer(keyedBy: Inner.self, forKey: .message) else {
            messageType = nil; requestId = nil; status = nil
            return
        }
        messageType = try inner.decodeIfPresent(String.self, forKey: .type)
        let payload = try? inner.nestedContainer(keyedBy: Payload.self, forKey: .payload)
        requestId = try payload?.decodeIfPresent(String.self, forKey: .requestId)
        status = try payload?.decodeIfPresent(String.self, forKey: .status)
    }
}
