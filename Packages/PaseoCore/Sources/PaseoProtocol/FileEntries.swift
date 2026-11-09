import Foundation

// Filesystem entry operations and conflict-checked text writes.
//
// Source: messages.ts `FileEntryCreateRequestSchema`, `FileEntryRenameRequestSchema`,
// `FileEntryDuplicateRequestSchema`, `FileEntryDeleteRequestSchema`,
// `FileEntryCreateResponseSchema`, `FileEntryRenameResponseSchema`,
// `FileEntryDuplicateResponseSchema`, `FileEntryDeleteResponseSchema`,
// `FileWriteRequestSchema`, `FileWriteResponseSchema`, `FileWriteResultSchema`,
// `FileVersionSchema` (reused from GitExtras.swift).
//
// Entry-operation failures come back as `success: false` with `error: string | null` —
// collisions surface the daemon's text verbatim; only the write path reports through the
// `FileWriteResult` union. Names on the wire: create and rename take the new `name`,
// not a path.

/// What to create. Source: messages.ts `FileEntryCreateRequestSchema.kind`.
public enum FileEntryKind: String, Sendable, Hashable, Encodable, CaseIterable {
    case file, directory
}

/// The outcome of a conflict-checked write.
/// Source: messages.ts `FileWriteResultSchema` discriminated union, `FileWriteResponseSchema`.
public enum FileWriteResult: Sendable, Hashable, Decodable {
    /// `written` — the file was replaced; carries the new stat.
    case written(modifiedAt: String, size: Int, revision: String?)
    /// `conflict` — `expectedModifiedAt` didn't match; carries the current version.
    case conflict(FileVersion)
    /// `error` — the daemon's message.
    case error(String)

    private enum K: String, CodingKey { case status, modifiedAt, size, revision, version, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .status) {
        case "written":
            self = .written(
                modifiedAt: try c.decode(String.self, forKey: .modifiedAt),
                size: try c.decode(Int.self, forKey: .size),
                revision: try c.decodeIfPresent(String.self, forKey: .revision))
        case "conflict":
            self = .conflict(try c.decode(FileVersion.self, forKey: .version))
        case "error":
            self = .error(try c.decode(String.self, forKey: .error))
        case let other:
            // Unknown status from a newer daemon: surface the raw tag as an error, not a throw.
            self = .error("Unknown write result status '\(other)'")
        }
    }
}

/// Source: messages.ts `FileWriteRequestSchema`, `FileWriteResponseSchema`.
/// Gate `features.workspaceFileEditing`.
public struct FileWriteRequest: PaseoRequest {
    public static let type = "fs.file.write.request"
    public static let responseType = "fs.file.write.response"
    public var requestId = ""
    public var cwd: String
    public var path: String
    public var content: String
    /// COMPAT(fileByteWrites): added in v0.13.0. Daemons without the feature write `content` as text.
    public var contentEncoding: String?
    /// Mandatory on the wire — no blind overwrite.
    public var expectedModifiedAt: String
    public var expectedRevision: String?

    public init(
        cwd: String, path: String, content: String, expectedModifiedAt: String,
        contentEncoding: String? = nil, expectedRevision: String? = nil
    ) {
        self.cwd = cwd
        self.path = path
        self.content = content
        self.expectedModifiedAt = expectedModifiedAt
        self.contentEncoding = contentEncoding
        self.expectedRevision = expectedRevision
    }

    public struct Response: Decodable, Sendable {
        public var result: FileWriteResult
        public var requestId: String
    }
}

/// Source: messages.ts `FileEntryCreateRequestSchema`, `FileEntryCreateResponseSchema`.
/// Gate `features.fsEntryOps`.
public struct FileEntryCreateRequest: PaseoRequest {
    public static let type = "fs.entry.create.request"
    public static let responseType = "fs.entry.create.response"
    public var requestId = ""
    public var cwd: String
    public var parentPath: String
    public var name: String
    public var kind: FileEntryKind

    public init(cwd: String, parentPath: String, name: String, kind: FileEntryKind) {
        self.cwd = cwd
        self.parentPath = parentPath
        self.name = name
        self.kind = kind
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var parentPath: String
        public var path: String?
        public var success: Bool
        public var error: String?
        public var requestId: String
    }
}

/// Source: messages.ts `FileEntryRenameRequestSchema`, `FileEntryRenameResponseSchema`.
/// Gate `features.fsEntryOps`. `name` is the new basename, not a path.
public struct FileEntryRenameRequest: PaseoRequest {
    public static let type = "fs.entry.rename.request"
    public static let responseType = "fs.entry.rename.response"
    public var requestId = ""
    public var cwd: String
    public var path: String
    /// The new basename.
    public var name: String

    public init(cwd: String, path: String, name: String) {
        self.cwd = cwd
        self.path = path
        self.name = name
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var path: String
        public var renamedPath: String?
        public var success: Bool
        public var error: String?
        public var requestId: String
    }
}

/// Source: messages.ts `FileEntryDuplicateRequestSchema`, `FileEntryDuplicateResponseSchema`.
/// Gate `features.fsEntryDuplicate`. The daemon copies server-side; no bytes round-trip.
public struct FileEntryDuplicateRequest: PaseoRequest {
    public static let type = "fs.entry.duplicate.request"
    public static let responseType = "fs.entry.duplicate.response"
    public var requestId = ""
    public var cwd: String
    public var path: String

    public init(cwd: String, path: String) {
        self.cwd = cwd
        self.path = path
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var path: String
        public var duplicatedPath: String?
        public var success: Bool
        public var error: String?
        public var requestId: String
    }
}

/// Source: messages.ts `FileEntryDeleteRequestSchema`, `FileEntryDeleteResponseSchema`.
/// Gate `features.fsEntryOps`. Unlink/rmdir only — no trash.
public struct FileEntryDeleteRequest: PaseoRequest {
    public static let type = "fs.entry.delete.request"
    public static let responseType = "fs.entry.delete.response"
    public var requestId = ""
    public var cwd: String
    public var path: String

    public init(cwd: String, path: String) {
        self.cwd = cwd
        self.path = path
    }

    public struct Response: Decodable, Sendable {
        public var cwd: String
        public var path: String
        public var success: Bool
        public var error: String?
        public var requestId: String
    }
}
