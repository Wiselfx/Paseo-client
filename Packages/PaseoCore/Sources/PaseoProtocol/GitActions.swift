import Foundation

// Git actions and the commit log: pull/merge, PR create/merge, forge auto-merge, and the
// commits-ahead-of-base list with a per-commit file diff.
//
// Source: messages.ts `CheckoutPullRequestSchema`, `CheckoutPullResponseSchema`,
// `CheckoutMergeRequestSchema`, `CheckoutMergeResponseSchema`,
// `CheckoutMergeFromBaseRequestSchema`, `CheckoutMergeFromBaseResponseSchema`,
// `CheckoutPrCreateRequestSchema`, `CheckoutPrCreateResponseSchema`,
// `CheckoutPrMergeRequestSchema`, `CheckoutPrMergeResponseSchema`,
// `CheckoutForgeSetAutoMergeRequestSchema`, `CheckoutForgeSetAutoMergeResponseSchema`,
// `CheckoutGithubSetAutoMergeRequestSchema` (COMPAT(githubAutoMergeRpc), remove after 2027-01-17),
// `CheckoutGithubSetAutoMergeResponseSchema` (same payload),
// `CheckoutCommitsListRequestSchema`, `CheckoutCommitsListResponseSchema`,
// `CheckoutCommitFileDiffRequestSchema`, `CheckoutCommitFileDiffResponseSchema`,
// `CheckoutCommitSchema`, `CheckoutCommitFileSchema`.
//
// Every response carries `error` typed as `CheckoutError | null` (messages.ts
// `CheckoutErrorSchema`), so `MERGE_CONFLICT` survives decoding as
// `CheckoutErrorCode.mergeConflict`. The entry-op RPCs carry a plain `string | null`
// error instead (see FileEntries.swift).

/// Merge strategies for opening and merging PRs and for forge auto-merge.
/// Source: messages.ts `CheckoutPrMergeRequestSchema.mergeMethod`, `CheckoutForgeSetAutoMergeRequestSchema.mergeMethod`.
public enum PullRequestMergeMethod: String, Sendable, Hashable, Encodable, CaseIterable {
    case merge, squash, rebase
}

/// Status of one file inside a commit. Source: messages.ts `CheckoutCommitFileSchema.status`.
public enum CheckoutCommitFileStatus: Sendable, Hashable, Decodable {
    case added, modified, deleted, renamed
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "added": self = .added
        case "modified": self = .modified
        case "deleted": self = .deleted
        case "renamed": self = .renamed
        case let other: self = .unknown(other)
        }
    }
}

/// One file touched by a commit. Source: messages.ts `CheckoutCommitFileSchema`.
public struct CheckoutCommitFile: Sendable, Hashable, Decodable, Identifiable {
    public var path: String
    public var additions: Int
    public var deletions: Int
    public var status: CheckoutCommitFileStatus?

    public var id: String { path }

    public init(path: String, additions: Int, deletions: Int, status: CheckoutCommitFileStatus? = nil) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.status = status
    }
}

/// One commit between the base ref and HEAD.
/// Source: messages.ts `CheckoutCommitSchema`.
public struct CheckoutCommit: Sendable, Hashable, Decodable, Identifiable {
    public var sha: String
    public var shortSha: String
    public var subject: String
    public var authorName: String
    /// ISO 8601 timestamp, as the daemon sends it.
    public var authorDate: String
    /// `false` means local-only (unpushed).
    public var isOnRemote: Bool
    /// COMPAT(commitBaseClassification): added in v0.2.0, remove after 2027-01-23.
    /// `true` means the commit is classified as living on the base branch.
    public var isOnBase: Bool?
    public var files: [CheckoutCommitFile]

    public var id: String { sha }

    public init(
        sha: String, shortSha: String, subject: String, authorName: String, authorDate: String,
        isOnRemote: Bool, isOnBase: Bool? = nil, files: [CheckoutCommitFile] = []
    ) {
        self.sha = sha
        self.shortSha = shortSha
        self.subject = subject
        self.authorName = authorName
        self.authorDate = authorDate
        self.isOnRemote = isOnRemote
        self.isOnBase = isOnBase
        self.files = files
    }
}

/// Source: messages.ts `CheckoutCommitFileDiffRequestSchema`, `CheckoutCommitFileDiffResponseSchema`.
public struct CheckoutCommitFileDiffRequest: PaseoRequest {
    public static let type = "checkout.commits.file_diff.request"
    public static let responseType = "checkout.commits.file_diff.response"
    public var requestId = ""
    public var cwd: String
    public var sha: String
    public var path: String

    public init(cwd: String, sha: String, path: String) {
        self.cwd = cwd
        self.sha = sha
        self.path = path
    }

    /// The null `file` covers absent or binary files.
    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var sha: String
        public var path: String
        public var file: ParsedDiffFile?
        public var error: CheckoutError?
        public var requestId: String
    }
}

/// Source: messages.ts `CheckoutCommitsListRequestSchema`, `CheckoutCommitsListResponseSchema`.
public struct CheckoutCommitsListRequest: PaseoRequest {
    public static let type = "checkout.commits.list.request"
    public static let responseType = "checkout.commits.list.response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var baseRef: String?
        public var commits: [CheckoutCommit]
        public var error: CheckoutError?
        public var requestId: String
    }
}

/// Source: messages.ts `CheckoutPullRequestSchema`, `CheckoutPullResponseSchema`,
/// `CheckoutMergeRequestSchema`, `CheckoutMergeResponseSchema`,
/// `CheckoutMergeFromBaseRequestSchema`, `CheckoutMergeFromBaseResponseSchema`.
/// The three responses share one payload shape.
public struct CheckoutMutationResponse: Decodable, Sendable {
    public var cwd: String
    public var success: Bool
    public var error: CheckoutError?
    public var requestId: String
}

/// Source: messages.ts `CheckoutPullRequestSchema`. No capability gate.
public struct CheckoutPullRequest: PaseoRequest {
    public static let type = "checkout_pull_request"
    public static let responseType = "checkout_pull_response"
    public var requestId = ""
    public var cwd: String
    public init(cwd: String) { self.cwd = cwd }
    public typealias Response = CheckoutMutationResponse
}

/// Source: messages.ts `CheckoutMergeRequestSchema`. No capability gate.
public struct CheckoutMergeRequest: PaseoRequest {
    public static let type = "checkout_merge_request"
    public static let responseType = "checkout_merge_response"
    public var requestId = ""
    public var cwd: String
    public var baseRef: String?
    /// `merge` or `squash` only; rebase is deliberately absent from this RPC.
    public var strategy: String?
    public var requireCleanTarget: Bool?

    public init(cwd: String, baseRef: String? = nil, strategy: String? = nil, requireCleanTarget: Bool? = nil) {
        self.cwd = cwd
        self.baseRef = baseRef
        self.strategy = strategy
        self.requireCleanTarget = requireCleanTarget
    }
    public typealias Response = CheckoutMutationResponse
}

/// Source: messages.ts `CheckoutMergeFromBaseRequestSchema`. No capability gate.
public struct CheckoutMergeFromBaseRequest: PaseoRequest {
    public static let type = "checkout_merge_from_base_request"
    public static let responseType = "checkout_merge_from_base_response"
    public var requestId = ""
    public var cwd: String
    public var baseRef: String?
    public var requireCleanTarget: Bool?

    public init(cwd: String, baseRef: String? = nil, requireCleanTarget: Bool? = nil) {
        self.cwd = cwd
        self.baseRef = baseRef
        self.requireCleanTarget = requireCleanTarget
    }
    public typealias Response = CheckoutMutationResponse
}

/// Source: messages.ts `CheckoutPrCreateRequestSchema`, `CheckoutPrCreateResponseSchema`.
/// No capability gate.
public struct CheckoutPrCreateRequest: PaseoRequest {
    public static let type = "checkout_pr_create_request"
    public static let responseType = "checkout_pr_create_response"
    public var requestId = ""
    public var cwd: String
    public var title: String?
    public var body: String?
    public var baseRef: String?

    public init(cwd: String, title: String? = nil, body: String? = nil, baseRef: String? = nil) {
        self.cwd = cwd
        self.title = title
        self.body = body
        self.baseRef = baseRef
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var url: String?
        public var number: Int?
        public var error: CheckoutError?
        public var requestId: String
    }
}

/// Source: messages.ts `CheckoutPrMergeRequestSchema`, `CheckoutPrMergeResponseSchema`.
/// No capability gate. `mergeMethod` is required on the wire.
public struct CheckoutPrMergeRequest: PaseoRequest {
    public static let type = "checkout_pr_merge_request"
    public static let responseType = "checkout_pr_merge_response"
    public var requestId = ""
    public var cwd: String
    public var mergeMethod: PullRequestMergeMethod

    public init(cwd: String, mergeMethod: PullRequestMergeMethod) {
        self.cwd = cwd
        self.mergeMethod = mergeMethod
    }
    public typealias Response = CheckoutMutationResponse
}

/// Source: messages.ts `CheckoutForgeSetAutoMergeResponseSchema` and the identical
/// legacy `CheckoutGithubSetAutoMergeResponseSchema`. Shared by both twins.
public struct CheckoutSetAutoMergeResponse: Decodable, Sendable {
    public var cwd: String
    public var enabled: Bool
    public var success: Bool
    public var error: CheckoutError?
    public var requestId: String
}

/// Source: messages.ts `CheckoutForgeSetAutoMergeRequestSchema`. Gate `features.checkoutForgeSetAutoMerge`.
public struct CheckoutForgeSetAutoMergeRequest: PaseoRequest {
    public static let type = "checkout.forge.set_auto_merge.request"
    public static let responseType = "checkout.forge.set_auto_merge.response"
    public var requestId = ""
    public var cwd: String
    public var enabled: Bool
    /// Deliberately absent on the wire when disabling; callers must not pass `mergeMethod`
    /// alongside `enabled: false` (older daemons expect the field missing or ignore it).
    public var mergeMethod: PullRequestMergeMethod?

    public init(cwd: String, enabled: Bool, mergeMethod: PullRequestMergeMethod? = nil) {
        self.cwd = cwd
        self.enabled = enabled
        self.mergeMethod = mergeMethod
    }
    public typealias Response = CheckoutSetAutoMergeResponse
}

/// COMPAT(githubAutoMergeRpc): legacy twin, remove after 2027-01-17.
/// Source: messages.ts `CheckoutGithubSetAutoMergeRequestSchema`. Gate `features.checkoutGithubSetAutoMerge`.
public struct CheckoutGithubSetAutoMergeRequest: PaseoRequest {
    public static let type = "checkout.github.set_auto_merge.request"
    public static let responseType = "checkout.github.set_auto_merge.response"
    public var requestId = ""
    public var cwd: String
    public var enabled: Bool
    public var mergeMethod: PullRequestMergeMethod?

    public init(cwd: String, enabled: Bool, mergeMethod: PullRequestMergeMethod? = nil) {
        self.cwd = cwd
        self.enabled = enabled
        self.mergeMethod = mergeMethod
    }
    public typealias Response = CheckoutSetAutoMergeResponse
}
