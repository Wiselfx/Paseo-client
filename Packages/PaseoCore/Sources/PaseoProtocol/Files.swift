import Foundation

// One-shot file explorer reads. Source: messages.ts `FileExplorerRequestSchema`,
// `FileExplorerResponseSchema`, `FileExplorerEntrySchema`, `FileExplorerFileSchema`,
// `FileExplorerDirectorySchema`.
//
// Live file watching (`fs.file.subscribe.request`) is not part of T7; the explorer re-reads on
// demand and the view can re-list after a mutation.

public enum FileExplorerEntryKind: Sendable, Hashable, Decodable {
    case file, directory
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "file": self = .file
        case "directory": self = .directory
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `FileExplorerEntrySchema`.
public struct FileExplorerEntry: Sendable, Hashable, Decodable, Identifiable {
    public var name: String
    public var path: String
    public var kind: FileExplorerEntryKind
    public var size: Int
    public var modifiedAt: String

    public var id: String { path }
    public var isDirectory: Bool { kind == .directory }
}

/// Source: messages.ts `FileExplorerDirectorySchema`.
public struct FileExplorerDirectory: Sendable, Hashable, Decodable {
    public var path: String
    public var entries: [FileExplorerEntry]
}

public enum FileExplorerFileKind: Sendable, Hashable, Decodable {
    case text, image, binary
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "text": self = .text
        case "image": self = .image
        case "binary": self = .binary
        case let other: self = .unknown(other)
        }
    }
}

public enum FileExplorerEncoding: Sendable, Hashable, Decodable {
    case utf8, base64, none
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "utf-8": self = .utf8
        case "base64": self = .base64
        case "none": self = .none
        case let other: self = .unknown(other)
        }
    }
}

/// Source: messages.ts `FileExplorerFileSchema`.
public struct FileExplorerFile: Sendable, Hashable, Decodable {
    public var path: String
    public var kind: FileExplorerFileKind
    public var encoding: FileExplorerEncoding
    public var content: String?
    public var mimeType: String?
    public var size: Int
    public var modifiedAt: String
    public var revision: String?

    /// The text when the daemon sent UTF-8 inline; nil for binary or base64 payloads.
    public var textContent: String? {
        encoding == .utf8 ? content : nil
    }
}

public enum FileExplorerMode: Sendable, Encodable, Hashable, Decodable {
    case list, file
    case unknown(String)

    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "list": self = .list
        case "file": self = .file
        case let other: self = .unknown(other)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .list: try c.encode("list")
        case .file: try c.encode("file")
        case .unknown(let raw): try c.encode(raw)
        }
    }
}

/// Source: messages.ts `FileExplorerRequestSchema`, `FileExplorerResponseSchema`.
public struct FileExplorerRequest: PaseoRequest {
    public static let type = "file_explorer_request"
    public static let responseType = "file_explorer_response"
    public var requestId = ""
    public var cwd: String
    public var path: String?
    public var mode: FileExplorerMode
    public var acceptBinary: Bool?
    public var maxBytes: Int?

    public init(
        cwd: String,
        mode: FileExplorerMode,
        path: String? = nil,
        maxBytes: Int? = nil,
        acceptBinary: Bool? = nil
    ) {
        self.cwd = cwd
        self.mode = mode
        self.path = path
        self.maxBytes = maxBytes
        self.acceptBinary = acceptBinary
    }

    public struct Response: Decodable, Sendable {
        public var requestId: String
        public var cwd: String
        public var path: String
        public var mode: FileExplorerMode
        public var directory: FileExplorerDirectory?
        public var file: FileExplorerFile?
        public var error: String?

        public init(
            requestId: String, cwd: String, path: String, mode: FileExplorerMode,
            directory: FileExplorerDirectory?, file: FileExplorerFile?, error: String?
        ) {
            self.requestId = requestId
            self.cwd = cwd
            self.path = path
            self.mode = mode
            self.directory = directory
            self.file = file
            self.error = error
        }
    }
}
