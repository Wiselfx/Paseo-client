import Foundation

/// A session message that has no correlated response.
///
/// Terminal input, directory subscriptions and terminal unsubscribe are fire-and-forget on the
/// wire: the daemon never answers them with a `*_response` frame. They cannot use
/// `PaseoRequest`, whose contract is a request/response pair.
public protocol PaseoOutboundMessage: Encodable, Sendable {
    /// `message.type` of the request, e.g. `terminal_input`.
    static var type: String { get }
}

/// Encodes `{"type":"session","message":{"type":M.type, …message fields}}`.
public struct SessionOutboundEnvelope<M: PaseoOutboundMessage>: Encodable {
    public let message: M
    public init(_ message: M) { self.message = message }

    private struct Body: Encodable {
        let message: M
        func encode(to encoder: Encoder) throws {
            try message.encode(to: encoder)
            var c = encoder.container(keyedBy: AnyKey.self)
            try c.encode(M.type, forKey: AnyKey("type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode("session", forKey: AnyKey("type"))
        try c.encode(Body(message: message), forKey: AnyKey("message"))
    }
}
