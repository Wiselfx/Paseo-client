import Foundation

// Pull request timeline: reviews, comments, and unknown kinds tolerated forward-compatibly.
//
// Source: messages.ts `PullRequestTimelineRequestSchema` (`packages/protocol/src/messages.ts:2573-2580`),
// `PullRequestTimelineResponseSchema` (`:6167-6179`), `PullRequestTimelineKnownErrorSchema` /
// `PullRequestTimelineErrorSchema` (`:6074-6099`), `PullRequestTimelineItemSchema` (`:6150-6165`,
// preprocess), `PullRequestTimelineReviewItemSchema` (`:6100-6113`),
// `PullRequestTimelineCommentItemSchema` (`:6115-6147`).
//
// The wire's `preprocess` collapses unknown item kinds onto "comment" and unknown error kinds onto
// "unknown". This client keeps them distinguishable instead: unknown items decode as `.unknown`
// (rendered as quiet rows) and unknown error kinds decode as `.unknown`. Either can be a newer
// daemon; both are preserved, not thrown.
//
// Note on nesting: inline comments carry `reviewId` to nest under a review, and `threadId`
// (or `location.threadId`) to group a thread; issue comments and general forge discussions have
// no file position. Layout order is the wire's original order.

/// Source: messages.ts `PullRequestTimelineErrorSchema`.
public enum PullRequestTimelineErrorKind: Sendable, Hashable, Decodable {
    case notFound, forbidden, unknown

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "not_found": self = .notFound
        case "forbidden": self = .forbidden
        case "unknown", _: self = .unknown
        }
    }
}

/// Source: messages.ts `PullRequestTimelineErrorSchema`.
public struct PullRequestTimelineError: Sendable, Hashable, Decodable {
    public var kind: PullRequestTimelineErrorKind
    public var message: String

    public init(kind: PullRequestTimelineErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }

    private enum K: String, CodingKey { case kind, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        kind = (try? c.decode(PullRequestTimelineErrorKind.self, forKey: .kind)) ?? .unknown
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
    }
}

/// A file position on an inline comment. Source: messages.ts `PullRequestTimelineCommentItemSchema.location`.
public struct PullRequestCommentLocation: Sendable, Hashable, Decodable {
    public var path: String
    public var line: Int?
    public var startLine: Int?
    public var threadId: String?
    public var isResolved: Bool?
    public var isOutdated: Bool?

    public init(
        path: String, line: Int? = nil, startLine: Int? = nil, threadId: String? = nil,
        isResolved: Bool? = nil, isOutdated: Bool? = nil
    ) {
        self.path = path
        self.line = line
        self.startLine = startLine
        self.threadId = threadId
        self.isResolved = isResolved
        self.isOutdated = isOutdated
    }
}

/// Source: messages.ts `PullRequestTimelineReviewItemSchema`.
public struct PullRequestTimelineReview: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    /// `approved`, `changes_requested` or `commented`; unknown states map to `.commented`.
    public var reviewState: PullRequestReviewVerdict
    public var author: String
    public var authorUrl: String?
    public var avatarUrl: String?
    public var body: String
    /// Unix milliseconds, as the daemon sends it.
    public var createdAt: Double
    public var url: String

    public init(
        id: String, reviewState: PullRequestReviewVerdict, author: String, authorUrl: String? = nil,
        avatarUrl: String? = nil, body: String, createdAt: Double, url: String
    ) {
        self.id = id
        self.reviewState = reviewState
        self.author = author
        self.authorUrl = authorUrl
        self.avatarUrl = avatarUrl
        self.body = body
        self.createdAt = createdAt
        self.url = url
    }

    private enum K: String, CodingKey {
        case id, author, authorUrl, avatarUrl, body, createdAt, url, reviewState
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        reviewState = (try? c.decode(PullRequestReviewVerdict.self, forKey: .reviewState)) ?? .commented
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "unknown"
        authorUrl = try c.decodeIfPresent(String.self, forKey: .authorUrl)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

/// The review verdict. Source: messages.ts `PullRequestTimelineReviewItemSchema.reviewState`.
public enum PullRequestReviewVerdict: Sendable, Hashable, Decodable {
    case approved, changesRequested, commented
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "approved": self = .approved
        case "changes_requested": self = .changesRequested
        case "commented": self = .commented
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `PullRequestTimelineCommentItemSchema`.
public struct PullRequestTimelineComment: Sendable, Hashable, Decodable, Identifiable {
    public var id: String
    public var author: String
    public var authorUrl: String?
    public var avatarUrl: String?
    public var body: String
    /// Unix milliseconds, as the daemon sends it.
    public var createdAt: Double
    public var url: String
    /// The review this inline comment belongs to; absent on issue comments and on older daemons.
    public var reviewId: String?
    /// Forge-neutral thread id grouping a discussion; absent on standalone comments.
    public var threadId: String?
    public var threadIsResolved: Bool?
    public var location: PullRequestCommentLocation?

    public init(
        id: String, author: String, authorUrl: String? = nil, avatarUrl: String? = nil,
        body: String, createdAt: Double, url: String, reviewId: String? = nil,
        threadId: String? = nil, threadIsResolved: Bool? = nil,
        location: PullRequestCommentLocation? = nil
    ) {
        self.id = id
        self.author = author
        self.authorUrl = authorUrl
        self.avatarUrl = avatarUrl
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.reviewId = reviewId
        self.threadId = threadId
        self.threadIsResolved = threadIsResolved
        self.location = location
    }

    private enum K: String, CodingKey {
        case id, author, authorUrl, avatarUrl, body, createdAt, url
        case reviewId, threadId, threadIsResolved, location
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "unknown"
        authorUrl = try c.decodeIfPresent(String.self, forKey: .authorUrl)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        reviewId = try c.decodeIfPresent(String.self, forKey: .reviewId)
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId)
        threadIsResolved = try c.decodeIfPresent(Bool.self, forKey: .threadIsResolved)
        location = try c.decodeIfPresent(PullRequestCommentLocation.self, forKey: .location)
    }
}

/// One timeline item. Source: messages.ts `PullRequestTimelineItemSchema` (kind `review` or `comment`).
public enum PullRequestTimelineItem: Sendable, Hashable, Decodable {
    case review(PullRequestTimelineReview)
    case comment(PullRequestTimelineComment)
    /// A newer daemon's item kind; kept as-is rather than collapsed onto comment.
    case unknown(kind: String)

    private enum K: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "review": self = .review(try PullRequestTimelineReview(from: decoder))
        case "comment": self = .comment(try PullRequestTimelineComment(from: decoder))
        default: self = .unknown(kind: kind)
        }
    }
}

/// Source: messages.ts `PullRequestTimelineRequestSchema`. No capability gate.
public struct PullRequestTimelineRequest: PaseoRequest {
    public static let type = "pull_request_timeline_request"
    public static let responseType = "pull_request_timeline_response"
    public var requestId = ""
    public var cwd: String
    public var prNumber: Int
    public var repoOwner: String
    public var repoName: String

    public init(cwd: String, prNumber: Int, repoOwner: String, repoName: String) {
        self.cwd = cwd
        self.prNumber = prNumber
        self.repoOwner = repoOwner
        self.repoName = repoName
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String?
        public var prNumber: Int?
        public var items: [PullRequestTimelineItem]
        public var truncated: Bool
        public var error: PullRequestTimelineError?
        public var requestId: String?
        public var githubFeaturesEnabled: Bool?
        /// Opaque on the wire; treat unrecognised strings as unknown.
        public var authState: JSONValue?

        private enum K: String, CodingKey {
            case cwd, prNumber, items, truncated, error, requestId
            case githubFeaturesEnabled, authState
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
            prNumber = try c.decodeIfPresent(Int.self, forKey: .prNumber)
            items = try c.decodeIfPresent([PullRequestTimelineItem].self, forKey: .items) ?? []
            truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
            error = try c.decodeIfPresent(PullRequestTimelineError.self, forKey: .error)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
            githubFeaturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .githubFeaturesEnabled)
            authState = try c.decodeIfPresent(JSONValue.self, forKey: .authState)
        }
    }
}
