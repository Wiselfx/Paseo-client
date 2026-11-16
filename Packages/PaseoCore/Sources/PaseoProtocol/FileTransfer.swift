import Foundation

// File upload frames: `FileBegin`/`FileChunk`/`FileEnd`, correlated by `requestId` to the
// `file.upload.request` that precedes them. The bytes stream outside the JSON send queue.
// Source: packages/protocol/src/binary-frames/file-transfer.ts

/// Source: `packages/protocol/src/binary-frames/file-transfer.ts` `FileTransferOpcode`.
public enum FileTransferOpcode: UInt8, Sendable, Hashable {
    case fileBegin = 0x10
    case fileChunk = 0x11
    case fileEnd = 0x12
}

/// The `encoding` field of `FileBeginMetadataSchema`. Unknown values round-trip verbatim so a
/// newer daemon teaching the codec a new encoding does not break decode.
public enum FileBeginEncoding: Sendable, Hashable, Codable {
    case utf8
    case binary
    case unknown(String)

    public var wireValue: String {
        switch self {
        case .utf8: "utf-8"
        case .binary: "binary"
        case .unknown(let raw): raw
        }
    }

    public init(wire: String) {
        switch wire {
        case "utf-8": self = .utf8
        case "binary": self = .binary
        default: self = .unknown(wire)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

/// Source: `FileBeginMetadataSchema` (`file-transfer.ts:12`). `revision` and `fileName` are
/// optional; everything else is required by the schema. `modifiedAt` stays an ISO-8601 string —
/// the daemon never parses it, and being lenient costs nothing.
public struct FileBeginMetadata: Sendable, Hashable, Codable {
    public var mime: String
    public var size: Int
    public var encoding: FileBeginEncoding
    public var modifiedAt: String
    public var revision: String?
    public var fileName: String?

    public init(
        mime: String, size: Int, encoding: FileBeginEncoding, modifiedAt: String,
        revision: String? = nil, fileName: String? = nil
    ) {
        self.mime = mime
        self.size = size
        self.encoding = encoding
        self.modifiedAt = modifiedAt
        self.revision = revision
        self.fileName = fileName
    }
}

/// One decoded file-transfer frame. Source: `FileTransferFrame` (`file-transfer.ts:40`).
public enum FileTransferFrame: Sendable, Hashable {
    case begin(requestId: String, metadata: FileBeginMetadata)
    case chunk(requestId: String, payload: Data)
    case end(requestId: String)
}

/// Encodes and decodes the exact byte layout of `file-transfer.ts:58-128`.
public enum FileTransferFrameCodec {
    /// `requestId` UTF-8, 1…255 bytes (`file-transfer.ts:142-151`).
    public static let maxRequestIdBytes = 255
    /// The metadata JSON must fit in a uint16 (`file-transfer.ts:63-65`).
    public static let maxMetadataBytes = 0xffff

    public enum EncodeError: Error, Sendable, Equatable {
        case requestIdEmpty
        case requestIdTooLong(Int)
        case metadataTooLong(Int)
    }

    public static func encode(_ frame: FileTransferFrame) throws -> Data {
        switch frame {
        case .begin(let requestId, let metadata):
            let requestIdBytes = try checkedRequestIdBytes(requestId)
            let metadataBytes = Array(metadataJSON(metadata).utf8)
            guard metadataBytes.count <= maxMetadataBytes else {
                throw EncodeError.metadataTooLong(metadataBytes.count)
            }
            var bytes = Data()
            bytes.append(FileTransferOpcode.fileBegin.rawValue)
            bytes.append(UInt8(requestIdBytes.count))
            bytes.append(contentsOf: requestIdBytes)
            bytes.append(UInt8((metadataBytes.count >> 8) & 0xff))
            bytes.append(UInt8(metadataBytes.count & 0xff))
            bytes.append(contentsOf: metadataBytes)
            return bytes

        case .chunk(let requestId, let payload):
            let requestIdBytes = try checkedRequestIdBytes(requestId)
            var bytes = Data()
            bytes.append(FileTransferOpcode.fileChunk.rawValue)
            bytes.append(UInt8(requestIdBytes.count))
            bytes.append(contentsOf: requestIdBytes)
            bytes.append(contentsOf: payload)
            return bytes

        case .end(let requestId):
            let requestIdBytes = try checkedRequestIdBytes(requestId)
            var bytes = Data()
            bytes.append(FileTransferOpcode.fileEnd.rawValue)
            bytes.append(UInt8(requestIdBytes.count))
            bytes.append(contentsOf: requestIdBytes)
            return bytes
        }
    }

    /// Mirrors `decodeFileTransferFrame` (`file-transfer.ts:88`): returns `nil` for anything a
    /// newer or older peer might reasonably produce rather than throwing.
    public static func decode(_ data: Data) -> FileTransferFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let opcodeByte = bytes[0]
        guard let opcode = FileTransferOpcode(rawValue: opcodeByte) else { return nil }
        let requestIdLength = Int(bytes[1])
        guard requestIdLength >= 1, requestIdLength <= bytes.count - 2 else { return nil }

        let requestId = String(decoding: bytes[2 ..< 2 + requestIdLength], as: UTF8.self)
        let body = Array(bytes[(2 + requestIdLength)...])

        switch opcode {
        case .fileBegin:
            guard body.count >= 2 else { return nil }
            let metadataLength = (Int(body[0]) << 8) | Int(body[1])
            guard metadataLength == body.count - 2 else { return nil }
            let metadataJSON = Array(body[2...])
            guard let metadata = parseMetadataJSON(metadataJSON) else { return nil }
            return .begin(requestId: requestId, metadata: metadata)

        case .fileChunk:
            return .chunk(requestId: requestId, payload: Data(body))

        case .fileEnd:
            guard body.isEmpty else { return nil }
            return .end(requestId: requestId)
        }
    }

    // MARK: JSON

    /// Hand-rolled so the key order is exactly `mime, size, encoding, modifiedAt, revision?,
    /// fileName?` regardless of platform JSON encoder quirks. The daemon parses JSON, not key
    /// order; determinism exists for tests and fixtures.
    static func metadataJSON(_ metadata: FileBeginMetadata) -> String {
        var json = "{\"mime\":"
        json += jsonString(metadata.mime)
        json += ",\"size\":\(metadata.size)"
        json += ",\"encoding\":"
        json += jsonString(metadata.encoding.wireValue)
        json += ",\"modifiedAt\":"
        json += jsonString(metadata.modifiedAt)
        if let revision = metadata.revision {
            json += ",\"revision\":"
            json += jsonString(revision)
        }
        if let fileName = metadata.fileName {
            json += ",\"fileName\":"
            json += jsonString(fileName)
        }
        json += "}"
        return json
    }

    /// Escapes a string as a JSON string literal, emitting UTF-8 bytes.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    static func parseMetadataJSON(_ bytes: [UInt8]) -> FileBeginMetadata? {
        guard let json = String(data: Data(bytes), encoding: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return nil }
        guard let mime = parsed["mime"] as? String, !mime.isEmpty,
            let sizeNumber = parsed["size"] as? NSNumber,
            sizeNumber.doubleValue == sizeNumber.doubleValue.rounded(),
            sizeNumber.int64Value >= 0,
            let size = Int(exactly: sizeNumber.int64Value),
            let encodingRaw = parsed["encoding"] as? String,
            let modifiedAt = parsed["modifiedAt"] as? String
        else { return nil }
        let revision = parsed["revision"] as? String
        let fileName = parsed["fileName"] as? String
        return FileBeginMetadata(
            mime: mime, size: size, encoding: FileBeginEncoding(wire: encodingRaw),
            modifiedAt: modifiedAt, revision: revision, fileName: fileName)
    }

    private static func checkedRequestIdBytes(_ requestId: String) throws -> [UInt8] {
        let bytes = Array(requestId.utf8)
        guard !bytes.isEmpty else { throw EncodeError.requestIdEmpty }
        guard bytes.count <= maxRequestIdBytes else { throw EncodeError.requestIdTooLong(bytes.count) }
        return bytes
    }
}
