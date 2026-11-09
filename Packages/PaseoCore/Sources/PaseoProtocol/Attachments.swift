import Foundation

// Image and file attachments. Source: messages.ts `ImageAttachmentSchema`,
// `AgentAttachmentSchema`, `AgentAttachmentsSchema`, `FileUploadRequestSchema`,
// `FileUploadResponseSchema`, `UploadedFileAttachmentSchema`.
//
// Forward compatibility: unknown attachment kinds decode into `.unknown` instead of failing the
// message, and every field the daemon may omit is optional here. Unlike the daemon's lenient
// normalization, this client never silently drops an attachment it was given.

public struct ImageAttachment: Sendable, Hashable, Codable {
    /// Base64-encoded image bytes.
    public var data: String
    /// e.g. `image/jpeg`, `image/png`.
    public var mimeType: String

    public init(data: String, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }

    public init(data: Data, mimeType: String) {
        self.init(data: data.base64EncodedString(), mimeType: mimeType)
    }

    /// Decoded bytes, or `nil` when the wire carried invalid base64.
    public var bytes: Data? { Data(base64Encoded: data) }
}

// MARK: - Structured attachments

public enum AgentAttachment: Sendable, Hashable, Decodable {
    case forgeChangeRequest(ForgeChangeRequestAttachment)
    case forgeIssue(ForgeIssueAttachment)
    /// COMPAT: legacy kind the daemon retained when forge-neutral kinds shipped.
    case githubPullRequest(GitHubPullRequestAttachment)
    /// COMPAT: legacy kind the daemon retained when forge-neutral kinds shipped.
    case githubIssue(GitHubIssueAttachment)
    case text(TextAttachment)
    case review(ReviewAttachment)
    case uploadedFile(UploadedFileAttachment)
    case unknown(type: String, raw: JSONValue)

    public struct ForgeChangeRequestAttachment: Sendable, Hashable, Codable {
        public var type = "forge_change_request"
        public var mimeType = "application/paseo-forge-change-request"
        public var forge: String?
        public var number: Int
        public var title: String
        public var url: String
        public var body: String?
        public var projectPath: String?
        public var baseRefName: String?
        public var headRefName: String?

        public init(
            forge: String? = nil, number: Int, title: String, url: String, body: String? = nil,
            projectPath: String? = nil, baseRefName: String? = nil, headRefName: String? = nil
        ) {
            self.forge = forge
            self.number = number
            self.title = title
            self.url = url
            self.body = body
            self.projectPath = projectPath
            self.baseRefName = baseRefName
            self.headRefName = headRefName
        }
    }

    public struct ForgeIssueAttachment: Sendable, Hashable, Codable {
        public var type = "forge_issue"
        public var mimeType = "application/paseo-forge-issue"
        public var forge: String?
        public var number: Int
        public var title: String
        public var url: String
        public var body: String?
        public var projectPath: String?

        public init(
            forge: String? = nil, number: Int, title: String, url: String, body: String? = nil,
            projectPath: String? = nil
        ) {
            self.forge = forge
            self.number = number
            self.title = title
            self.url = url
            self.body = body
            self.projectPath = projectPath
        }
    }

    public struct GitHubPullRequestAttachment: Sendable, Hashable, Codable {
        public var type = "github_pr"
        public var mimeType = "application/github-pr"
        public var number: Int
        public var title: String
        public var url: String
        public var body: String?
        public var baseRefName: String?
        public var headRefName: String?

        public init(
            number: Int, title: String, url: String, body: String? = nil,
            baseRefName: String? = nil, headRefName: String? = nil
        ) {
            self.number = number
            self.title = title
            self.url = url
            self.body = body
            self.baseRefName = baseRefName
            self.headRefName = headRefName
        }
    }

    public struct GitHubIssueAttachment: Sendable, Hashable, Codable {
        public var type = "github_issue"
        public var mimeType = "application/github-issue"
        public var number: Int
        public var title: String
        public var url: String
        public var body: String?

        public init(number: Int, title: String, url: String, body: String? = nil) {
            self.number = number
            self.title = title
            self.url = url
            self.body = body
        }
    }

    public struct TextAttachment: Sendable, Hashable, Codable {
        public var type = "text"
        public var mimeType = "text/plain"
        /// Only `chat_history` is defined today; unknown values survive here.
        public var contextKind: String?
        public var title: String?
        public var text: String
        public var externalResource: ExternalResource?

        public init(
            text: String, title: String? = nil, contextKind: String? = nil,
            externalResource: ExternalResource? = nil
        ) {
            self.text = text
            self.title = title
            self.contextKind = contextKind
            self.externalResource = externalResource
        }

        public struct ExternalResource: Sendable, Hashable, Codable {
            public var provider: String
            public var providerLabel: String
            public var resourceType: String
            public var id: String
            public var identifier: String
            public var title: String
            public var url: String

            public init(
                provider: String, providerLabel: String, resourceType: String, id: String,
                identifier: String, title: String, url: String
            ) {
                self.provider = provider
                self.providerLabel = providerLabel
                self.resourceType = resourceType
                self.id = id
                self.identifier = identifier
                self.title = title
                self.url = url
            }
        }
    }

    public struct ReviewAttachment: Sendable, Hashable, Codable {
        public var type = "review"
        public var mimeType = "application/paseo-review"
        public var cwd: String
        public var mode: Mode
        public var baseRef: String?
        public var comments: [Comment]

        public enum Mode: Sendable, Hashable, Codable {
            case uncommitted, base, all
            case unknown(String)

            public init(from decoder: Decoder) throws {
                switch try decoder.singleValueContainer().decode(String.self) {
                case "uncommitted": self = .uncommitted
                case "base": self = .base
                case "all": self = .all
                case let other: self = .unknown(other)
                }
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .uncommitted: try c.encode("uncommitted")
                case .base: try c.encode("base")
                case .all: try c.encode("all")
                case .unknown(let raw): try c.encode(raw)
                }
            }
        }

        public init(cwd: String, mode: Mode, baseRef: String? = nil, comments: [Comment] = []) {
            self.cwd = cwd
            self.mode = mode
            self.baseRef = baseRef
            self.comments = comments
        }

        public struct Comment: Sendable, Hashable, Codable {
            public var filePath: String
            public var side: Side
            public var lineNumber: Int
            public var body: String
            public var context: Context

            public enum Side: Sendable, Hashable, Codable {
                case old, new
                case unknown(String)

                public init(from decoder: Decoder) throws {
                    switch try decoder.singleValueContainer().decode(String.self) {
                    case "old": self = .old
                    case "new": self = .new
                    case let other: self = .unknown(other)
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var c = encoder.singleValueContainer()
                    switch self {
                    case .old: try c.encode("old")
                    case .new: try c.encode("new")
                    case .unknown(let raw): try c.encode(raw)
                    }
                }
            }

            public init(filePath: String, side: Side, lineNumber: Int, body: String, context: Context) {
                self.filePath = filePath
                self.side = side
                self.lineNumber = lineNumber
                self.body = body
                self.context = context
            }
        }

        public struct Context: Sendable, Hashable, Codable {
            public var hunkHeader: String
            public var targetLine: Line
            public var lines: [Line]

            public init(hunkHeader: String, targetLine: Line, lines: [Line]) {
                self.hunkHeader = hunkHeader
                self.targetLine = targetLine
                self.lines = lines
            }
        }

        public struct Line: Sendable, Hashable, Codable {
            public var oldLineNumber: Int?
            public var newLineNumber: Int?
            public var type: LineType
            public var content: String

            public enum LineType: Sendable, Hashable, Codable {
                case add, remove, context
                case unknown(String)

                public init(from decoder: Decoder) throws {
                    switch try decoder.singleValueContainer().decode(String.self) {
                    case "add": self = .add
                    case "remove": self = .remove
                    case "context": self = .context
                    case let other: self = .unknown(other)
                    }
                }

                public func encode(to encoder: Encoder) throws {
                    var c = encoder.singleValueContainer()
                    switch self {
                    case .add: try c.encode("add")
                    case .remove: try c.encode("remove")
                    case .context: try c.encode("context")
                    case .unknown(let raw): try c.encode(raw)
                    }
                }
            }

            public init(
                oldLineNumber: Int? = nil, newLineNumber: Int? = nil, type: LineType,
                content: String
            ) {
                self.oldLineNumber = oldLineNumber
                self.newLineNumber = newLineNumber
                self.type = type
                self.content = content
            }
        }
    }

    /// A file already uploaded out of band with `FileUploadRequest`. `path` is daemon-side.
    public struct UploadedFileAttachment: Sendable, Hashable, Codable, Identifiable {
        public var type = "uploaded_file"
        public var id: String
        public var fileName: String
        public var mimeType: String
        public var size: Int
        public var path: String

        public init(id: String, fileName: String, mimeType: String, size: Int, path: String) {
            self.id = id
            self.fileName = fileName
            self.mimeType = mimeType
            self.size = size
            self.path = path
        }
    }

    /// The wire `type`, including a newer value this client only keeps raw.
    public var type: String {
        switch self {
        case .forgeChangeRequest: "forge_change_request"
        case .forgeIssue: "forge_issue"
        case .githubPullRequest: "github_pr"
        case .githubIssue: "github_issue"
        case .text: "text"
        case .review: "review"
        case .uploadedFile: "uploaded_file"
        case .unknown(let type, _): type
        }
    }

    /// The uploaded file, when this is one. Convenience for the composer and send path.
    public var uploadedFile: UploadedFileAttachment? {
        if case .uploadedFile(let file) = self { return file }
        return nil
    }

    private enum K: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let type = try decoder.discriminator()
        switch type {
        case "forge_change_request":
            self = .forgeChangeRequest(try ForgeChangeRequestAttachment(from: decoder))
        case "forge_issue":
            self = .forgeIssue(try ForgeIssueAttachment(from: decoder))
        case "github_pr":
            self = .githubPullRequest(try GitHubPullRequestAttachment(from: decoder))
        case "github_issue":
            self = .githubIssue(try GitHubIssueAttachment(from: decoder))
        case "text":
            self = .text(try TextAttachment(from: decoder))
        case "review":
            self = .review(try ReviewAttachment(from: decoder))
        case "uploaded_file":
            self = .uploadedFile(try UploadedFileAttachment(from: decoder))
        default:
            self = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
    }
}

extension AgentAttachment: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .forgeChangeRequest(let attachment): try attachment.encode(to: encoder)
        case .forgeIssue(let attachment): try attachment.encode(to: encoder)
        case .githubPullRequest(let attachment): try attachment.encode(to: encoder)
        case .githubIssue(let attachment): try attachment.encode(to: encoder)
        case .text(let attachment): try attachment.encode(to: encoder)
        case .review(let attachment): try attachment.encode(to: encoder)
        case .uploadedFile(let attachment): try attachment.encode(to: encoder)
        case .unknown(_, let raw): try raw.encode(to: encoder)
        }
    }
}

// MARK: - Upload

/// `file.upload.request`: the JSON frame that precedes the byte stream. Source:
/// `FileUploadRequestSchema` (messages.ts). Bytes travel as `FileBegin`/`FileChunk`/`FileEnd`
/// binary frames correlated by `requestId`, not on this frame.
public struct FileUploadRequest: PaseoRequest {
    public static let type = "file.upload.request"
    public static let responseType = "file.upload.response"
    public var requestId = ""
    public var fileName: String
    public var mimeType: String
    public var size: Int
    /// ISO-8601. The daemon rejects a file without a parseable timestamp.
    public var modifiedAt: String

    public init(fileName: String, mimeType: String, size: Int, modifiedAt: String) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.modifiedAt = modifiedAt
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        /// `nil` when the upload failed; the daemon explains in `error`.
        public var file: AgentAttachment.UploadedFileAttachment?
        public var error: String?
    }
}
