import Foundation
import PaseoKit
import PaseoProtocol

// M7d: rewind the conversation (and optionally the working tree) to an earlier message.
// Per PHASE2-CONVENTIONS: the store holds the RPC and the error path; new files own the feature.
// The rewind response is an ordinary correlated `agent.rewind.response`, so it rides `client.send`.
// The rewindable-or-not decision needs the snapshot, so it lives on ConversationStore; the host
// feature gate lives on HostSession. Both are plain computed properties — no new state.

/// What the user chose to rewind. `unknown` carries a future mode verbatim rather than refusing
/// to decode the wire value.
public enum RewindScope: Sendable, Hashable, Codable {
    case conversation
    case files
    case both
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        switch try c.decode(String.self) {
        case "conversation": self = .conversation
        case "files": self = .files
        case "both": self = .both
        case let other: self = .unknown(other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .conversation: try c.encode("conversation")
        case .files: try c.encode("files")
        case .both: try c.encode("both")
        case .unknown(let raw): try c.encode(raw)
        }
    }

    /// The wire mode, unchanged for unknown values.
    var mode: AgentRewindMode {
        switch self {
        case .conversation: .conversation
        case .files: .files
        case .both: .both
        case .unknown(let raw): .unknown(raw)
        }
    }
}

/// Provider rewind support on this agent, read from its snapshot. `isAvailable` is the union and
/// drives the affordance's visibility; `menu` is the scope list the provider supports.
public struct RewindCapabilities: Sendable, Hashable {
    public var conversation: Bool
    public var files: Bool
    public var both: Bool

    public var isAvailable: Bool { conversation || files || both }

    /// De-duplicated scopes the provider supports, in upstream order
    /// (use-rewind-capabilities.ts): conversation, files, then both. Nothing is inferred from one
    /// flag onto another — the advertised flags are shown verbatim.
    public var menu: [RewindScope] {
        var scopes: [RewindScope] = []
        if conversation { scopes.append(.conversation) }
        if files { scopes.append(.files) }
        if both { scopes.append(.both) }
        return scopes
    }

    init(_ snapshot: AgentSnapshot?) {
        let flags = snapshot?.capabilities
        conversation = flags?.supportsRewindConversation == true
        files = flags?.supportsRewindFiles == true
        both = flags?.supportsRewindBoth == true
    }
}

extension ConversationStore {
    /// The provider's advertised rewind support, per snapshot. The host feature gate is
    /// `session.isRewindSupportedByHost`; use both flags to decide visibility.
    public var rewindCapabilities: RewindCapabilities {
        RewindCapabilities(agent)
    }

    /// Rewinds to `messageId` (M7d). Nil on `agent.rewind.response` with `ok == true`;
    /// otherwise the daemon's refusal message, the transport error, or a nil-connection note.
    ///
    /// Scopes the provider doesn't advertise are refused client-side without hitting the wire.
    /// The host gate is `session.isRewindSupportedByHost`; the view checks it before offering
    /// the menu, so this method only enforces the provider half.
    public func rewind(toMessageId messageId: String, scope: RewindScope) async -> String? {
        guard rewindCapabilities.menu.contains(scope) else {
            return "This provider does not support rewinding that scope."
        }
        guard let client else { return "Not connected." }
        do {
            let response = try await client.send(
                RewindAgentRequest(agentId: agentId, messageId: messageId, mode: scope.mode))
            guard response.ok else {
                return response.error ?? "The daemon refused to rewind."
            }
            return nil
        } catch {
            return paseoStoreErrorText(error)
        }
    }
}

extension HostSession {
    /// `server_info.features.rewind`. Exposed to views as one plain flag.
    public var isRewindSupportedByHost: Bool {
        serverInfo?.hasFeature("rewind") ?? false
    }
}
