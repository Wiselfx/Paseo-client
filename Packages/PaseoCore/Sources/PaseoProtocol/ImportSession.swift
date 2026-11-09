import Foundation

// Importing an existing CLI/terminal agent session from the host into a Paseo agent.
// Source: messages.ts `FetchRecentProviderSessionsRequestMessageSchema` (:1443),
// `FetchRecentProviderSessionsResponseMessageSchema` (:4485),
// `RecentProviderSessionDescriptorPayloadSchema` (:946),
// `ImportAgentRequestMessageSchema` (:1937), `AgentResumedStatusPayloadSchema` (:4091),
// `AgentCreateFailedStatusPayloadSchema` (:4085); features `importSessionWorkspaceTarget`
// (:3988) and `importSessionSearch` (:3990). The upstream sheet fans out one list request
// per enabled provider (`packages/app/src/components/import-session-sheet.tsx`), imports
// via `importAgent` with `providerId` + `providerHandleId`
// (`packages/client/src/daemon-client.ts:231-240,3801-3826`).

// Source: messages.ts `RecentProviderSessionDescriptorPayloadSchema` (:946)

/// One recent provider session the host can import. `providerHandleId` is the provider's own
/// session id; `cwd` is the directory the session ran in.
public struct RecentProviderSessionDescriptor: Sendable, Hashable, Decodable, Identifiable {
    public var providerId: String
    public var providerLabel: String
    public var providerHandleId: String
    public var cwd: String
    public var title: String?
    public var firstPromptPreview: String?
    public var lastPromptPreview: String?
    public var lastActivityAt: String

    /// Stable identity, matching upstream's `providerId:providerHandleId` dedupe key
    /// (`import-session-sheet-view-model.ts` `aggregateSessionEntries`).
    public var id: String { "\(providerId):\(providerHandleId)" }

    public init(
        providerId: String, providerLabel: String, providerHandleId: String, cwd: String,
        title: String? = nil, firstPromptPreview: String? = nil, lastPromptPreview: String? = nil,
        lastActivityAt: String
    ) {
        self.providerId = providerId
        self.providerLabel = providerLabel
        self.providerHandleId = providerHandleId
        self.cwd = cwd
        self.title = title
        self.firstPromptPreview = firstPromptPreview
        self.lastPromptPreview = lastPromptPreview
        self.lastActivityAt = lastActivityAt
    }
}

// Source: messages.ts `FetchRecentProviderSessionsRequestMessageSchema`

/// Lists recent sessions for one provider (the sheet sends one request per enabled provider,
/// so a dead provider only fails its own rows). `query` needs `features.importSessionSearch`;
/// omit it on daemons without the flag. `limit` is 1...200 upstream; paging grows the limit
/// instead of carrying an offset.
public struct FetchRecentProviderSessionsRequest: PaseoRequest {
    public static let type = "fetch_recent_provider_sessions_request"
    public static let responseType = "fetch_recent_provider_sessions_response"
    public var requestId = ""
    /// Scopes the listing to one directory (the sheet's "This workspace"); nil lists the host.
    public var cwd: String?
    public var providers: [String]?
    public var since: String?
    public var limit: Int?
    public var query: String?

    public init(
        cwd: String? = nil, providers: [String]? = nil, since: String? = nil,
        limit: Int? = nil, query: String? = nil
    ) {
        self.cwd = cwd
        self.providers = providers
        self.since = since
        self.limit = limit
        self.query = query
    }

    // Source: messages.ts `FetchRecentProviderSessionsResponseMessageSchema`
    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var entries: [RecentProviderSessionDescriptor]
        /// Sessions the daemon already filtered out because a Paseo agent exists for them.
        public var filteredAlreadyImportedCount: Int?
        public var providerErrors: [ProviderError]?

        public struct ProviderError: Decodable, Sendable, Hashable {
            public var provider: String
            public var message: String
        }
    }
}

// Source: messages.ts `ImportAgentRequestMessageSchema`

/// Imports one recent session. The sheet uses the `providerId` + `providerHandleId` form;
/// the `provider` + `sessionId` form is the same request with the other identity pair.
/// `workspaceId` needs `features.importSessionWorkspaceTarget` and must match `cwd`'s
/// workspace on the daemon.
///
/// The daemon answers on the `status` stream, correlated by `requestId`, with either
/// `agent_resumed` (the imported agent) or `agent_create_failed` (with `error`) — the same
/// shape as `CreateAgentRequest`.
public struct ImportAgentRequest: PaseoRequest {
    public static let type = "import_agent_request"
    public static let responseType = "status"
    public var requestId = ""
    /// AgentProvider enum value, for the `provider` + `sessionId` form.
    public var provider: String?
    public var providerId: String?
    public var sessionId: String?
    public var providerHandleId: String?
    public var cwd: String?
    public var workspaceId: String?
    public var labels: [String: String]?

    public init(
        providerId: String, providerHandleId: String, cwd: String? = nil,
        workspaceId: String? = nil, labels: [String: String]? = nil
    ) {
        self.providerId = providerId
        self.providerHandleId = providerHandleId
        self.cwd = cwd
        self.workspaceId = workspaceId
        self.labels = labels
    }

    /// Either success (with `agent`) or `agent_create_failed` (with `error`).
    public struct Response: Decodable, Sendable {
        public var status: String
        public var requestId: String
        public var agent: AgentSnapshot?
        public var error: String?
        public var errorCode: String?
    }
}
