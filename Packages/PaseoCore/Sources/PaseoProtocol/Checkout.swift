import Foundation

// The git half of a workspace: status, the legacy JSON diff stream, commit/push and the
// subscription release used to tear the diff stream down.
//
// Source: messages.ts `CheckoutStatusRequestSchema`, `CheckoutStatusResponseSchema`,
// `CheckoutStatusUpdateSchema`, `CheckoutErrorSchema`, `CheckoutPrStatusSchema`,
// `SubscribeCheckoutDiffRequestSchema`, `CheckoutDiffGetRequestSchema`,
// `UnsubscribeCheckoutDiffRequestSchema`, `CheckoutDiffUpdateSchema`, `CheckoutCommitRequestSchema`,
// `CheckoutPushRequestSchema`, `CheckoutRefreshRequestSchema`, `SubscriptionReleaseRequestSchema`.
//
// The binary `diff.subscribe.request` pipeline (§4.1) is deliberately not implemented here: the
// legacy JSON stream works on every daemon and is what T7 ships.

public enum CheckoutErrorCode: Sendable, Hashable, Decodable {
    case notGitRepo, notAllowed, mergeConflict, unknownCode
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "NOT_GIT_REPO": self = .notGitRepo
        case "NOT_ALLOWED": self = .notAllowed
        case "MERGE_CONFLICT": self = .mergeConflict
        case "UNKNOWN": self = .unknownCode
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `CheckoutErrorSchema`.
public struct CheckoutError: Sendable, Hashable, Decodable {
    public var code: CheckoutErrorCode
    public var message: String
    public init(code: CheckoutErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CheckoutAheadBehind: Sendable, Hashable, Decodable {
    public var ahead: Int
    public var behind: Int
    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }
}

public enum CheckoutMergeable: Sendable, Hashable, Decodable {
    case mergeable, conflicting, unknownState
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "MERGEABLE": self = .mergeable
        case "CONFLICTING": self = .conflicting
        case "UNKNOWN": self = .unknownState
        case let other: self = .unknown(other)
        }
    }
}

public struct CheckoutPrCheck: Sendable, Hashable, Decodable {
    public var name: String
    public var status: String
    public var url: String?
    public var workflow: String?
    public var duration: String?
    public var checkRunId: Int?
    public var workflowRunId: Int?
    public var traits: [String]?
}

/// The open PR/MR for the current branch. Source: messages.ts `CheckoutPrStatusSchema`.
public struct CheckoutPrStatus: Sendable, Hashable, Decodable {
    public var forge: String?
    public var projectPath: String?
    public var number: Int?
    public var url: String
    public var title: String
    public var state: String
    public var baseRefName: String
    public var headRefName: String
    public var isMerged: Bool
    public var isDraft: Bool?
    public var mergeable: CheckoutMergeable
    public var checks: [CheckoutPrCheck]
    public var checksStatus: String?
    public var reviewDecision: String?
    public var repoOwner: String?
    public var repoName: String?
    /// Open facts envelopes. Kept raw: `forgeSpecific` is a facts-family tag, not a brand.
    public var github: JSONValue?
    public var forgeSpecific: JSONValue?

    private enum K: String, CodingKey { case mergeable, checks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        mergeable = (try? c.decodeIfPresent(CheckoutMergeable.self, forKey: .mergeable)) ?? .unknownState
        checks = (try? c.decodeIfPresent([CheckoutPrCheck].self, forKey: .checks)) ?? []

        let all = try decoder.container(keyedBy: AllKeys.self)
        forge = try all.decodeIfPresent(String.self, forKey: .forge)
        projectPath = try all.decodeIfPresent(String.self, forKey: .projectPath)
        number = try all.decodeIfPresent(Int.self, forKey: .number)
        url = try all.decode(String.self, forKey: .url)
        title = try all.decode(String.self, forKey: .title)
        state = try all.decode(String.self, forKey: .state)
        baseRefName = try all.decode(String.self, forKey: .baseRefName)
        headRefName = try all.decode(String.self, forKey: .headRefName)
        isMerged = try all.decode(Bool.self, forKey: .isMerged)
        isDraft = try all.decodeIfPresent(Bool.self, forKey: .isDraft)
        checksStatus = try all.decodeIfPresent(String.self, forKey: .checksStatus)
        reviewDecision = try all.decodeIfPresent(String.self, forKey: .reviewDecision)
        repoOwner = try all.decodeIfPresent(String.self, forKey: .repoOwner)
        repoName = try all.decodeIfPresent(String.self, forKey: .repoName)
        github = try all.decodeIfPresent(JSONValue.self, forKey: .github)
        forgeSpecific = try all.decodeIfPresent(JSONValue.self, forKey: .forgeSpecific)
    }

    private enum AllKeys: String, CodingKey {
        case forge, projectPath, number, url, title, state, baseRefName, headRefName, isMerged
        case isDraft, checksStatus, reviewDecision, repoOwner, repoName, github, forgeSpecific
    }
}

/// The PR facts attached to a status update or returned by `checkout_pr_status_request`.
/// Source: messages.ts `CheckoutPrStatusPayloadSchema`.
public struct CheckoutPrStatusPayload: Sendable, Hashable, Decodable {
    public var cwd: String
    public var status: CheckoutPrStatus?
    public var githubFeaturesEnabled: Bool
    /// `z.unknown()` on the wire; decode as an opaque value and read `authStateText`.
    public var authState: JSONValue?
    public var forge: String?
    public var error: CheckoutError?

    public var authStateText: String? { authState?.stringValue }
}

/// Source: messages.ts `CheckoutStatusResponseSchema` (the three union shapes flattened; the
/// not-git shape simply leaves the git-only fields null).
public struct CheckoutStatus: Sendable, Hashable, Decodable {
    public var cwd: String
    public var isGit: Bool
    public var isPaseoOwnedWorktree: Bool
    public var repoRoot: String?
    public var mainRepoRoot: String?
    public var currentBranch: String?
    public var isDirty: Bool?
    public var baseRef: String?
    public var baseRefExact: String?
    public var comparisonBaseRef: String?
    /// The full `<branch>@{upstream}` ref git resolved; never compose `origin/<branch>`.
    public var upstreamRef: String?
    public var aheadBehind: CheckoutAheadBehind?
    public var aheadOfOrigin: Int?
    public var behindOfOrigin: Int?
    public var hasRemote: Bool
    public var remoteUrl: String?
    public var error: CheckoutError?

    public var isClean: Bool { isDirty == false }
}

/// Source: messages.ts `CheckoutStatusRequestSchema`.
public struct CheckoutStatusRequest: PaseoRequest {
    public static let type = "checkout_status_request"
    public static let responseType = "checkout_status_response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public typealias Response = CheckoutStatus
}

/// A pushed git status. Source: messages.ts `CheckoutStatusUpdateSchema`.
public struct CheckoutStatusUpdate: Sendable, Decodable {
    public var status: CheckoutStatus
    public var subscriptionId: String?
    public var prStatus: CheckoutPrStatusPayload?

    private enum K: String, CodingKey { case subscriptionId, prStatus }

    public init(from decoder: Decoder) throws {
        status = try CheckoutStatus(from: decoder)
        let c = try decoder.container(keyedBy: K.self)
        subscriptionId = try c.decodeIfPresent(String.self, forKey: .subscriptionId)
        prStatus = try c.decodeIfPresent(CheckoutPrStatusPayload.self, forKey: .prStatus)
    }

    public init(status: CheckoutStatus, subscriptionId: String?, prStatus: CheckoutPrStatusPayload?) {
        self.status = status
        self.subscriptionId = subscriptionId
        self.prStatus = prStatus
    }
}

/// Source: messages.ts `CheckoutPrStatusRequestSchema`, `CheckoutPrStatusResponseSchema`.
public struct CheckoutPrStatusRequest: PaseoRequest {
    public static let type = "checkout_pr_status_request"
    public static let responseType = "checkout_pr_status_response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public typealias Response = CheckoutPrStatusPayload
}

public enum DiffLineType: Sendable, Hashable, Decodable {
    case add, remove, context, header
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "add": self = .add
        case "remove": self = .remove
        case "context": self = .context
        case "header": self = .header
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `HighlightTokenSchema`.
public struct DiffHighlightToken: Sendable, Hashable, Decodable {
    public var text: String
    /// Compound syntax-highlighter class names such as `heading meta`.
    public var style: String?
}

/// Source: messages.ts `DiffLineSchema`.
public struct DiffLine: Sendable, Hashable, Decodable {
    public var type: DiffLineType
    public var content: String
    public var tokens: [DiffHighlightToken]?
}

/// Source: messages.ts `DiffHunkSchema`.
public struct DiffHunk: Sendable, Hashable, Decodable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [DiffLine]
}

public enum ParsedDiffFileStatus: Sendable, Hashable, Decodable {
    case ok, tooLarge, binary
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "ok": self = .ok
        case "too_large": self = .tooLarge
        case "binary": self = .binary
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `ParsedDiffFileSchema`.
public struct ParsedDiffFile: Sendable, Hashable, Decodable, Identifiable {
    public var path: String
    /// COMPAT(diffOldPath): present for renames on newer daemons.
    public var oldPath: String?
    public var isNew: Bool
    public var isDeleted: Bool
    public var additions: Int
    public var deletions: Int
    public var hunks: [DiffHunk]
    public var status: ParsedDiffFileStatus?

    public var id: String { oldPath.map { "\($0)->\(path)" } ?? path }
}

/// Source: messages.ts `CheckoutDiffCompareSchema`.
public struct CheckoutDiffCompare: Sendable, Hashable, Encodable {
    public enum Mode: String, Sendable, Encodable, Hashable {
        case uncommitted, base, all
    }

    public var mode: Mode
    public var baseRef: String?
    public var ignoreWhitespace: Bool?

    public init(mode: Mode, baseRef: String? = nil, ignoreWhitespace: Bool? = nil) {
        self.mode = mode
        self.baseRef = baseRef
        self.ignoreWhitespace = ignoreWhitespace
    }
}

/// One diff snapshot. The same payload backs the subscribe response, the one-shot read and the
/// pushed update; `subscriptionId` is absent on the one-shot read. Source: messages.ts
/// `CheckoutDiffSubscriptionPayloadSchema`, `SubscribeCheckoutDiffResponseSchema`,
/// `CheckoutDiffGetResponseSchema`, `CheckoutDiffUpdateSchema`.
public struct CheckoutDiff: Sendable, Hashable, Decodable {
    public var subscriptionId: String?
    public var cwd: String
    public var files: [ParsedDiffFile]
    public var error: CheckoutError?
    /// COMPAT(diffTooLarge): absent on older daemons.
    public var diffTooLarge: Bool?

    public var additions: Int { files.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    public var isTooLarge: Bool { diffTooLarge == true }
}

/// Source: messages.ts `SubscribeCheckoutDiffRequestSchema`.
public struct SubscribeCheckoutDiffRequest: PaseoRequest {
    public static let type = "subscribe_checkout_diff_request"
    public static let responseType = "subscribe_checkout_diff_response"
    public var requestId = ""
    public var subscriptionId: String?
    public var cwd: String
    public var compare: CheckoutDiffCompare

    public init(cwd: String, compare: CheckoutDiffCompare, subscriptionId: String? = nil) {
        self.cwd = cwd
        self.compare = compare
        self.subscriptionId = subscriptionId
    }

    public typealias Response = CheckoutDiff
}

/// Source: messages.ts `CheckoutDiffGetRequestSchema`.
public struct CheckoutDiffGetRequest: PaseoRequest {
    public static let type = "checkout.diff.get.request"
    public static let responseType = "checkout.diff.get.response"
    public var requestId = ""
    public var cwd: String
    public var compare: CheckoutDiffCompare
    public init(cwd: String, compare: CheckoutDiffCompare) {
        self.cwd = cwd
        self.compare = compare
    }

    public typealias Response = CheckoutDiff
}

/// Fire-and-forget release for the legacy diff stream. Source: messages.ts
/// `UnsubscribeCheckoutDiffRequestSchema` — no correlated response, so callers must not wait on it.
public struct UnsubscribeCheckoutDiffRequest: PaseoRequest {
    public static let type = "unsubscribe_checkout_diff_request"
    public static let responseType = "unsubscribe_checkout_diff_response"
    public var requestId = ""
    public var subscriptionId: String
    public init(subscriptionId: String) { self.subscriptionId = subscriptionId }

    public struct Response: Decodable, Sendable {
        public var requestId: String?

        public init(requestId: String?) { self.requestId = requestId }
    }

    // The wire schema has no `requestId` (the RPC is fire-and-forget), so don't send one.
    private enum K: String, CodingKey { case subscriptionId }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(subscriptionId, forKey: .subscriptionId)
    }
}

/// Modern owned-subscription teardown. Source: messages.ts `SubscriptionReleaseRequestSchema`.
public struct SubscriptionReleaseRequest: PaseoRequest {
    public static let type = "subscription.release.request"
    public static let responseType = "subscription.release.response"
    public var requestId = ""
    public var subscriptionId: String
    public init(subscriptionId: String) { self.subscriptionId = subscriptionId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var subscriptionId: String

        public init(requestId: String, subscriptionId: String) {
            self.requestId = requestId
            self.subscriptionId = subscriptionId
        }
    }
}

/// Source: messages.ts `CheckoutCommitRequestSchema`, `CheckoutCommitResponseSchema`.
public struct CheckoutCommitRequest: PaseoRequest {
    public static let type = "checkout_commit_request"
    public static let responseType = "checkout_commit_response"
    public var requestId = ""
    public var cwd: String
    public var message: String?
    public var addAll: Bool?
    public init(cwd: String, message: String? = nil, addAll: Bool? = nil) {
        self.cwd = cwd
        self.message = message
        self.addAll = addAll
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var success: Bool
        public var error: CheckoutError?

        public init(requestId: String, cwd: String, success: Bool, error: CheckoutError?) {
            self.requestId = requestId
            self.cwd = cwd
            self.success = success
            self.error = error
        }
    }
}

/// Source: messages.ts `CheckoutPushRequestSchema`, `CheckoutPushResponseSchema`.
public struct CheckoutPushRequest: PaseoRequest {
    public static let type = "checkout_push_request"
    public static let responseType = "checkout_push_response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var success: Bool
        public var error: CheckoutError?

        public init(requestId: String, cwd: String, success: Bool, error: CheckoutError?) {
            self.requestId = requestId
            self.cwd = cwd
            self.success = success
            self.error = error
        }
    }
}

/// Source: messages.ts `CheckoutRefreshRequestSchema`, `CheckoutRefreshResponseSchema`.
public struct CheckoutRefreshRequest: PaseoRequest {
    public static let type = "checkout.refresh.request"
    public static let responseType = "checkout.refresh.response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var success: Bool
        public var error: CheckoutError?

        public init(requestId: String, cwd: String, success: Bool, error: CheckoutError?) {
            self.requestId = requestId
            self.cwd = cwd
            self.success = success
            self.error = error
        }
    }
}
