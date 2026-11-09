import Foundation

// Project settings: project config (paseo.json) read/write with optimistic concurrency, and
// project icons.
//
// Sources: messages.ts `ReadProjectConfigRequestMessageSchema`,
// `WriteProjectConfigRequestMessageSchema`, `ReadProjectConfigResponseMessageSchema`,
// `WriteProjectConfigResponseMessageSchema`, `ProjectIconGetRequestMessageSchema`,
// `ProjectIconGetResponseMessageSchema`, `ProjectIconSetRequestSchema`,
// `ProjectIconSetResponseSchema`, `ProjectIconSourceSchema`, and `PaseoConfigRevisionSchema` /
// `PaseoConfigRawSchema` (packages/protocol/src/messages.ts :1741-1757, :5483-5525, :3060-3064,
// :6484-6494, :1019-1041; paseo-config-schema.ts:74-112).
//
// `config` is carried as the raw `JSONValue` object, not a typed schema: the daemon treats it as
// passthrough, and a typed round trip would silently drop `servicePorts`, `metadataGeneration`
// and any keys a newer daemon adds. The store only edits the keys it manages (`worktree.setup`,
// `worktree.teardown`, `scripts`) and re-encodes the rest untouched.
//
// `expectedRevision` is an object (`{ mtimeMs, size }`), not a string — an object revision.
// Write responses return config/revision non-null on ok:true; read returns them
// required-nullable (null when there is no paseo.json). Stale writes answer ok:false with
// `stale_project_config` carrying `currentRevision` — not an exception.

/// Optimistic-concurrency handle for `paseo.json`. Source: paseo-config-schema.ts
/// `PaseoConfigRevisionSchema` (`z.object({ mtimeMs: number, size: number })`).
public struct PaseoProjectConfigRevision: Sendable, Hashable, Codable {
    public var mtimeMs: Double
    public var size: Double

    public init(mtimeMs: Double, size: Double) {
        self.mtimeMs = mtimeMs
        self.size = size
    }
}

/// In-band failure of a project config RPC. Source: paseo-config-schema.ts
/// `ProjectConfigRpcErrorSchema` (discriminated on `code`). Unknown codes keep the raw string.
public enum ProjectConfigRpcError: Sendable, Hashable, Decodable, Equatable {
    case projectNotFound
    case invalidProjectConfig
    case staleProjectConfig(currentRevision: PaseoProjectConfigRevision?)
    case writeFailed
    case unknown(String)

    private enum K: String, CodingKey { case code, currentRevision }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? ""
        switch code {
        case "project_not_found": self = .projectNotFound
        case "invalid_project_config": self = .invalidProjectConfig
        case "stale_project_config":
            self = .staleProjectConfig(
                currentRevision: try? c.decodeIfPresent(
                    PaseoProjectConfigRevision.self, forKey: .currentRevision))
        case "write_failed": self = .writeFailed
        default: self = .unknown(code)
        }
    }

    public var userMessage: String {
        switch self {
        case .projectNotFound: "This project is no longer registered on the host."
        case .invalidProjectConfig: "The project's paseo.json could not be parsed."
        case .staleProjectConfig: "This file changed on the host."
        case .writeFailed: "The change could not be saved."
        case .unknown(let code): "The request failed (\(code))."
        }
    }
}

/// Source: messages.ts `ReadProjectConfigRequestMessageSchema`.
public struct ReadProjectConfigRequest: PaseoRequest {
    public static let type = "read_project_config_request"
    public static let responseType = "read_project_config_response"
    public var requestId = ""
    public var repoRoot: String
    public init(repoRoot: String) { self.repoRoot = repoRoot }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var repoRoot: String
        /// `ok:false` → `error` is set and config/revision are nil. `ok:true` → config/revision
        /// are required-nullable (null when there is no paseo.json).
        public var ok: Bool
        public var config: JSONValue?
        public var revision: PaseoProjectConfigRevision?
        public var hasUncommittedWorktreeSetupChanges: Bool?
        public var error: ProjectConfigRpcError?

        private enum K: String, CodingKey {
            case requestId, repoRoot, ok, config, revision, hasUncommittedWorktreeSetupChanges, error
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            repoRoot = try c.decodeIfPresent(String.self, forKey: .repoRoot) ?? ""
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            if ok {
                config = try c.decodeIfPresent(JSONValue.self, forKey: .config)
                revision = try c.decodeIfPresent(
                    PaseoProjectConfigRevision.self, forKey: .revision)
            } else {
                config = nil
                revision = nil
            }
            hasUncommittedWorktreeSetupChanges = try c.decodeIfPresent(
                Bool.self, forKey: .hasUncommittedWorktreeSetupChanges)
            error = ok ? nil : (try? c.decode(ProjectConfigRpcError.self, forKey: .error))
        }
    }
}

/// Source: messages.ts `WriteProjectConfigRequestMessageSchema` /
/// `ReadProjectConfigResponseMessageSchema` (both responses share a shape).
public struct WriteProjectConfigRequest: PaseoRequest {
    public static let type = "write_project_config_request"
    public static let responseType = "write_project_config_response"
    public var requestId = ""
    public var repoRoot: String
    public var config: JSONValue
    /// `null` when the file was read as absent (or when the host should fail the write on
    /// any existing file). Serialized as an explicit `null`, never omitted.
    public var expectedRevision: PaseoProjectConfigRevision?

    private enum K: String, CodingKey { case requestId, repoRoot, config, expectedRevision }

    public init(repoRoot: String, config: JSONValue, expectedRevision: PaseoProjectConfigRevision?) {
        self.repoRoot = repoRoot
        self.config = config
        self.expectedRevision = expectedRevision
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(repoRoot, forKey: .repoRoot)
        try c.encode(config, forKey: .config)
        if let expectedRevision {
            try c.encode(expectedRevision, forKey: .expectedRevision)
        } else {
            // Required-but-nullable on the wire; the daemon rejects a missing key.
            try c.encodeNil(forKey: .expectedRevision)
        }
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var repoRoot: String
        public var ok: Bool
        public var config: JSONValue?
        public var revision: PaseoProjectConfigRevision?
        public var hasUncommittedWorktreeSetupChanges: Bool?
        public var error: ProjectConfigRpcError?

        private enum K: String, CodingKey {
            case requestId, repoRoot, ok, config, revision, hasUncommittedWorktreeSetupChanges, error
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            repoRoot = try c.decodeIfPresent(String.self, forKey: .repoRoot) ?? ""
            ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
            if ok {
                config = try c.decodeIfPresent(JSONValue.self, forKey: .config)
                revision = try c.decodeIfPresent(
                    PaseoProjectConfigRevision.self, forKey: .revision)
            } else {
                config = nil
                revision = nil
            }
            hasUncommittedWorktreeSetupChanges = try c.decodeIfPresent(
                Bool.self, forKey: .hasUncommittedWorktreeSetupChanges)
            error = ok ? nil : (try? c.decode(ProjectConfigRpcError.self, forKey: .error))
        }
    }
}

/// The `source` discriminated union of `project.icon.set.request`. Source: messages.ts
/// `ProjectIconSourceSchema`.
public enum ProjectIconSource: Sendable, Hashable, Encodable {
    case automatic
    /// Base64-encoded image bytes; the daemon never fetches a URL.
    case upload(data: String)

    private enum K: String, CodingKey { case type, data }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .automatic:
            try c.encode("automatic", forKey: .type)
        case .upload(let data):
            try c.encode("upload", forKey: .type)
            try c.encode(data, forKey: .data)
        }
    }
}

/// Source: messages.ts `ProjectIconGetRequestMessageSchema` /
/// `ProjectIconGetResponseMessageSchema`.
public struct ProjectIconGetRequest: PaseoRequest {
    public static let type = "project.icon.get.request"
    public static let responseType = "project.icon.get.response"
    public var requestId = ""
    public var projectId: String
    public init(projectId: String) { self.projectId = projectId }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var projectId: String
        public var icon: Icon?
        public var error: String?

        public struct Icon: Sendable, Hashable, Decodable {
            public var data: String
            public var mimeType: String
        }

        private enum K: String, CodingKey { case requestId, projectId, icon, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            projectId = try c.decodeIfPresent(String.self, forKey: .projectId) ?? ""
            icon = try c.decodeIfPresent(Icon.self, forKey: .icon)
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}

/// Source: messages.ts `ProjectIconSetRequestSchema` / `ProjectIconSetResponseSchema`.
public struct ProjectIconSetRequest: PaseoRequest {
    public static let type = "project.icon.set.request"
    public static let responseType = "project.icon.set.response"
    public var requestId = ""
    public var projectId: String
    public var source: ProjectIconSource

    public init(projectId: String, source: ProjectIconSource) {
        self.projectId = projectId
        self.source = source
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var projectId: String
        public var accepted: Bool
        public var error: String?

        private enum K: String, CodingKey { case requestId, projectId, accepted, error }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            requestId = try c.decodeIfPresent(String.self, forKey: .requestId) ?? ""
            projectId = try c.decodeIfPresent(String.self, forKey: .projectId) ?? ""
            accepted = try c.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
            error = try c.decodeIfPresent(String.self, forKey: .error)
        }
    }
}
