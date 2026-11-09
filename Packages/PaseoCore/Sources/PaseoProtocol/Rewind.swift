import Foundation

// Rewind: restore the conversation (and optionally the files) to a point earlier in this agent.
// Source: messages.ts `AgentRewindModeSchema`, `AgentRewindRequestMessageSchema`,
// `AgentRewindResponseMessageSchema`, and the snapshot capabilities at `messages.ts:417`-`433`.
//
// Capability gate: `server_info.features.rewind` (v0.1.X-compat flag) AND the per-provider
// `capabilities.supportsRewind*` flags on the agent snapshot. A submitted prompt is not
// rewindable until the provider has acknowledged it (`providerMessageId` is set on the row).

/// Provider rewind support, carried by the snapshot (`CapabilityFlagsSchema.catchall(boolean)` —
/// unknown keys are ignored).
public struct AgentCapabilities: Sendable, Hashable, Decodable {
    public var supportsRewindConversation: Bool
    public var supportsRewindFiles: Bool
    public var supportsRewindBoth: Bool

    public init(
        supportsRewindConversation: Bool = false,
        supportsRewindFiles: Bool = false,
        supportsRewindBoth: Bool = false
    ) {
        self.supportsRewindConversation = supportsRewindConversation
        self.supportsRewindFiles = supportsRewindFiles
        self.supportsRewindBoth = supportsRewindBoth
    }

    private enum K: String, CodingKey {
        case supportsRewindConversation, supportsRewindFiles, supportsRewindBoth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        supportsRewindConversation =
            try c.decodeIfPresent(Bool.self, forKey: .supportsRewindConversation) ?? false
        supportsRewindFiles =
            try c.decodeIfPresent(Bool.self, forKey: .supportsRewindFiles) ?? false
        supportsRewindBoth =
            try c.decodeIfPresent(Bool.self, forKey: .supportsRewindBoth) ?? false
    }
}

/// `conversation` truncates the timeline; `files` restores the working tree; `both` does both.
public enum AgentRewindMode: Sendable, Hashable, Codable {
    case conversation
    case files
    case both
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self =
            switch try c.decode(String.self) {
            case "conversation": .conversation
            case "files": .files
            case "both": .both
            case let other: .unknown(other)
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
}

public struct RewindAgentRequest: PaseoRequest {
    public static let type = "agent.rewind.request"
    public static let responseType = "agent.rewind.response"

    public var requestId = ""
    public var agentId: String
    /// The message to rewind to. Sent as `messageId`; the daemon resolves submitted prompts to
    /// their provider ids itself.
    public var messageId: String
    public var mode: AgentRewindMode

    public init(agentId: String, messageId: String, mode: AgentRewindMode) {
        self.agentId = agentId
        self.messageId = messageId
        self.mode = mode
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String?
        public var agentId: String?
        public var ok: Bool
        public var error: String?

        private enum K: String, CodingKey { case requestId, agentId, ok, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}
