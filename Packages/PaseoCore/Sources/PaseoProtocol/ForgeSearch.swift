import Foundation

// Forge issue/PR search for the composer's "Add issue or PR" picker.
// Source: messages.ts `ForgeSearchRequestSchema` (:2666), `ForgeSearchResponseSchema` (:6295),
// `GitHubSearchRequestSchema` (:2683, COMPAT githubSearchRpc legacy fallback),
// `GitHubSearchResponseSchema` (:6303), `GitHubSearchItemSchema` (:2637),
// `ForgeSearchItemSchema` (:2654, kind `change_request`), `ForgeAuthState` (:5757, opaque on
// the wire: `z.unknown().optional()`, so unrecognised values decode as `.unknown`, never a
// failure). Feature gate: `forgeSearch` (:3862, COMPAT forgeSearch).

// Source: messages.ts `GitHubSearchItemSchema`

/// One issue or change request from forge search. `kind` is normalized to the forge-neutral
/// pair (`issue` / `change_request`); legacy `pr` / `github-issue` / `github-pr` decode into
/// the same cases, matching upstream's `normalizeLegacyGitHubSearchPayload`.
public struct ForgeSearchItem: Sendable, Hashable, Decodable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case issue
        case changeRequest
        case unknown(String)
    }

    public var kind: Kind
    public var forge: String?
    /// Wire `number` is `z.number()` (not int); decoded via Double, nil when unusable.
    public var number: Int?
    public var title: String
    public var url: String
    public var state: String
    public var body: String?
    public var labels: [String]
    public var projectPath: String?
    public var baseRefName: String?
    public var headRefName: String?
    public var updatedAt: String?

    /// Picker row identity, upstream's `${kind}:${number}` option id.
    public var id: String { "\(kind.wireValue):\(number ?? -1)" }

    private enum K: String, CodingKey {
        case kind, forge, number, title, url, state, body, labels, projectPath, baseRefName
        case headRefName, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil {
        case "issue", "github-issue": kind = .issue
        case "change_request", "pr", "github-pr": kind = .changeRequest
        case let other? where !other.isEmpty: kind = .unknown(other)
        default: kind = .unknown("")
        }
        forge = try c.decodeIfPresent(String.self, forKey: .forge)
        number = ((try? c.decodeIfPresent(Double.self, forKey: .number)) ?? nil).map { Int($0) }
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body)
        labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? []
        projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath)
        baseRefName = try c.decodeIfPresent(String.self, forKey: .baseRefName)
        headRefName = try c.decodeIfPresent(String.self, forKey: .headRefName)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public init(
        kind: Kind, forge: String? = nil, number: Int?, title: String, url: String,
        state: String = "open", body: String? = nil, labels: [String] = [],
        projectPath: String? = nil, baseRefName: String? = nil, headRefName: String? = nil,
        updatedAt: String? = nil
    ) {
        self.kind = kind
        self.forge = forge
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.body = body
        self.labels = labels
        self.projectPath = projectPath
        self.baseRefName = baseRefName
        self.headRefName = headRefName
        self.updatedAt = updatedAt
    }

    /// The attachment this row becomes when picked, forge-neutral (upstream
    /// `buildForgeAttachment`): change requests and issues both carry the forge when known.
    public var asAttachment: AgentAttachment? {
        guard let number, number > 0 else { return nil }
        switch kind {
        case .changeRequest:
            return .forgeChangeRequest(
                AgentAttachment.ForgeChangeRequestAttachment(
                    forge: forge, number: number, title: title, url: url, body: body,
                    projectPath: projectPath, baseRefName: baseRefName, headRefName: headRefName))
        case .issue:
            return .forgeIssue(
                AgentAttachment.ForgeIssueAttachment(
                    forge: forge, number: number, title: title, url: url, body: body,
                    projectPath: projectPath))
        case .unknown:
            return nil
        }
    }
}

extension ForgeSearchItem.Kind {
    /// The modern request's kind spelling.
    public var wireValue: String {
        switch self {
        case .issue: "issue"
        case .changeRequest: "change_request"
        case .unknown(let value): value
        }
    }

    /// The legacy request's kind spelling (COMPAT githubSearchKind).
    public var legacyWireValue: String {
        switch self {
        case .issue: "github-issue"
        case .changeRequest: "github-pr"
        case .unknown(let value): value
        }
    }
}

// Source: messages.ts `ForgeAuthState` — see the existing `ForgeAuthState` in GitExtras.swift
// (same opaque wire value); reused here rather than redeclared.

// Source: messages.ts `ForgeSearchRequestSchema`

/// Searches issues and change requests for one workspace (`cwd`). `kinds` omitted means both.
/// Requires `features.forgeSearch`; older daemons answer the legacy `github_search_request`
/// instead (the store picks the transport).
public struct ForgeSearchRequest: PaseoRequest {
    public static let type = "forge.search.request"
    public static let responseType = "forge.search.response"
    public var requestId = ""
    public var cwd: String
    public var query: String
    public var limit: Int?
    /// Wire kind spellings; the store sends the neutral pair.
    public var kinds: [String]?

    public init(cwd: String, query: String, limit: Int? = nil, kinds: [String]? = nil) {
        self.cwd = cwd
        self.query = query
        self.limit = limit
        self.kinds = kinds
    }

    // Source: messages.ts `ForgeSearchResponsePayloadSchema`
    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var items: [ForgeSearchItem]
        public var authState: JSONValue?
        public var error: String?

        private enum K: String, CodingKey { case requestId, items, authState, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            // Items are `z.unknown()` upstream and filtered per item; one bad item must not
            // sink the list.
            let raw = try c.decodeIfPresent([JSONValue].self, forKey: .items) ?? []
            items = decodeForgeItems(raw)
            authState = try c.decodeIfPresent(JSONValue.self, forKey: .authState)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

// Source: messages.ts `GitHubSearchRequestSchema` (COMPAT githubSearchRpc)

/// The legacy fallback for daemons without `features.forgeSearch`. Same fields; the response
/// adds `featuresEnabled` / `githubFeaturesEnabled`, which the store folds into `authState`.
public struct GitHubSearchRequest: PaseoRequest {
    public static let type = "github_search_request"
    public static let responseType = "github_search_response"
    public var requestId = ""
    public var cwd: String
    public var query: String
    public var limit: Int?
    public var kinds: [String]?

    public init(cwd: String, query: String, limit: Int? = nil, kinds: [String]? = nil) {
        self.cwd = cwd
        self.query = query
        self.limit = limit
        self.kinds = kinds
    }

    // Source: messages.ts `GitHubSearchResponsePayloadSchema`
    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var items: [ForgeSearchItem]
        public var featuresEnabled: Bool?
        public var authState: JSONValue?
        public var githubFeaturesEnabled: Bool?
        public var error: String?

        private enum K: String, CodingKey {
            case requestId, items, featuresEnabled, authState, githubFeaturesEnabled, error
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            // Same per-item tolerance as the forge response.
            let raw = try c.decodeIfPresent([JSONValue].self, forKey: .items) ?? []
            items = decodeForgeItems(raw)
            featuresEnabled = try c.decodeIfPresent(Bool.self, forKey: .featuresEnabled)
            authState = try c.decodeIfPresent(JSONValue.self, forKey: .authState)
            githubFeaturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .githubFeaturesEnabled)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

/// Decodes search items one by one, dropping the ones that don't fit (upstream safeParse).
private func decodeForgeItems(_ values: [JSONValue]) -> [ForgeSearchItem] {
    values.compactMap { value in
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ForgeSearchItem.self, from: data)
    }
}
