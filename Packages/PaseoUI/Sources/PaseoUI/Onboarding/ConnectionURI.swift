#if canImport(UIKit)
import Foundation

/// Parsing and validating the Advanced connection URI on the connect screen.
/// `ws(s)://host[:port][/ws]` — nothing else; the daemon's endpoint is always `/ws`.
public enum ConnectionURI {
    public struct Parsed: Equatable, Sendable {
        /// Complete URL, ready for `DaemonEndpoint(url:)`. Path is always `/ws`.
        public let url: URL
        public let host: String
        public let port: Int
        public let isTLS: Bool
        /// Host without brackets — the default label for a saved host.
        public let displayHost: String
    }

    public enum Result: Equatable {
        /// Nothing typed; the form falls back to host/port/TLS fields.
        case empty
        case valid(Parsed)
        case invalid(String)
    }

    /// Normalizes and validates the raw field. Empty input is `.empty`, not an error.
    public static func parse(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        guard trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://") else {
            return .invalid("Start with ws:// or wss://.")
        }
        let isTLS = trimmed.hasPrefix("wss://")

        guard var components = URLComponents(string: trimmed), let host = components.host else {
            return .invalid("That doesn't look like a host address.")
        }
        let displayHost = host
        guard !displayHost.isEmpty else {
            return .invalid("The URI needs a host, e.g. wss://example.com:6767/ws.")
        }
        if components.user != nil || components.password != nil {
            return .invalid("The URI can't carry credentials; use the password field.")
        }
        if components.query != nil || components.fragment != nil {
            return .invalid("The URI can't have a query or fragment.")
        }
        let path = components.path
        if !path.isEmpty, path != "/ws", path != "/ws/" {
            return .invalid("The daemon lives at ws://…/ws (path is always /ws).")
        }
        let port = components.port ?? (isTLS ? 443 : 80)

        components.scheme = isTLS ? "wss" : "ws"
        components.path = "/ws"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            return .invalid("That doesn't look like a host address.")
        }
        return .valid(
            Parsed(url: url, host: displayHost, port: port, isTLS: isTLS, displayHost: displayHost))
    }

    /// Inline message for the field, or nil when the input is empty or valid.
    public static func validationError(_ raw: String) -> String? {
        if case .invalid(let message) = parse(raw) { return message }
        return nil
    }

    /// The normalized string stored on the saved host — stable and credential-free.
    public static func normalized(_ raw: String) -> String? {
        if case .valid(let parsed) = parse(raw) { return parsed.url.absoluteString }
        return nil
    }
}
#endif
