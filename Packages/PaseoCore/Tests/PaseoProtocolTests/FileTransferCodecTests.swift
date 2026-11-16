import Foundation
import PaseoFixtures
import PaseoProtocol
import Testing

/// The file-transfer frame codec, tested byte-for-byte against frames produced by the actual
/// upstream codec (`packages/protocol/src/binary-frames/file-transfer.ts`), captured by
/// `Tools/capture-file-transfer.mjs` into `Fixtures/file-upload/frames.json`.
@Suite struct FileTransferCodecTests {
    @Test func decodesEveryUpstreamFrameByteForByte() throws {
        let frames = try Fixture.fileUploadFrames()
        #expect(frames.count == 7)
        for frame in frames {
            let decoded = try #require(
                FileTransferFrameCodec.decode(frame.encoded),
                "upstream frame \(frame.name) did not decode")
            switch frame.name {
            case "file-begin", "file-begin-no-optional-fields", "file-begin-utf8-encoding":
                guard case .begin(let requestId, let metadata) = decoded else {
                    Issue.record("expected .begin for \(frame.name)")
                    continue
                }
                let expected = try #require(frame.metadata)
                #expect(requestId == frame.requestId)
                #expect(metadata.mime == expected.mime)
                #expect(metadata.size == expected.size)
                #expect(metadata.encoding.wireValue == expected.encoding)
                #expect(metadata.modifiedAt == expected.modifiedAt)
                #expect(metadata.revision == expected.revision)
                #expect(metadata.fileName == expected.fileName)

            case "file-chunk", "file-chunk-1024", "file-chunk-empty":
                guard case .chunk(let requestId, let payload) = decoded else {
                    Issue.record("expected .chunk for \(frame.name)")
                    continue
                }
                #expect(requestId == frame.requestId)
                #expect(payload == frame.payload)

            case "file-end":
                guard case .end(let requestId) = decoded else {
                    Issue.record("expected .end for \(frame.name)")
                    continue
                }
                #expect(requestId == frame.requestId)

            default:
                Issue.record("unhandled fixture \(frame.name)")
            }

            // Decoding and re-encoding must be the identity on upstream bytes.
            #expect(try FileTransferFrameCodec.encode(decoded) == frame.encoded)
        }
    }

    @Test func encodesAgainstUpstreamFixtureBytes() throws {
        for frame in try Fixture.fileUploadFrames() {
            let toEncode: FileTransferFrame
            switch frame.opcode {
            case FileTransferOpcode.fileBegin.rawValue:
                let expected = try #require(frame.metadata)
                toEncode = .begin(
                    requestId: frame.requestId,
                    metadata: FileBeginMetadata(
                        mime: expected.mime, size: expected.size,
                        encoding: FileBeginEncoding(wire: expected.encoding),
                        modifiedAt: expected.modifiedAt,
                        revision: expected.revision, fileName: expected.fileName))
            case FileTransferOpcode.fileChunk.rawValue:
                toEncode = .chunk(
                    requestId: frame.requestId, payload: try #require(frame.payload))
            default:
                toEncode = .end(requestId: frame.requestId)
            }
            #expect(
                try FileTransferFrameCodec.encode(toEncode) == frame.encoded,
                "encoding \(frame.name) diverged from the upstream codec")
        }
    }

    @Test func decodeRejectsGarbage() {
        #expect(FileTransferFrameCodec.decode(Data()) == nil)
        #expect(FileTransferFrameCodec.decode(Data([0x10])) == nil)
        #expect(FileTransferFrameCodec.decode(Data([0x20, 0x00])) == nil)
        #expect(FileTransferFrameCodec.decode(Data([0x11, 0x00])) == nil)
        #expect(FileTransferFrameCodec.decode(Data([0x11, 0x05, 0x61])) == nil)
        #expect(FileTransferFrameCodec.decode(Data([0x12, 0x01, 0x61, 0x62])) == nil)
        // Begin: metadata length prefix does not match the body.
        #expect(FileTransferFrameCodec.decode(Data([0x10, 0x02, 0x61, 0x62, 0x00, 0x03, 0x7b])) == nil)
        // Begin: metadata is not JSON.
        #expect(
            FileTransferFrameCodec.decode(
                Data([0x10, 0x01, 0x61, 0x00, 0x05, 0xff, 0xff, 0xff, 0xff, 0xff])) == nil)
        // Begin: JSON is fine but not the schema (size missing).
        let noSize = #"{"mime":"text/plain","encoding":"binary","modifiedAt":"2026-11-09T00:00:00.000Z"}"#
        var bytes = Data([0x10, 0x01, 0x61])
        let json = Array(noSize.utf8)
        bytes.append(UInt8((json.count >> 8) & 0xff))
        bytes.append(UInt8(json.count & 0xff))
        bytes.append(contentsOf: json)
        #expect(FileTransferFrameCodec.decode(bytes) == nil)
    }

    @Test func encodeRejectsBadInputs() throws {
        #expect(throws: FileTransferFrameCodec.EncodeError.requestIdEmpty) {
            try FileTransferFrameCodec.encode(.end(requestId: ""))
        }
        // 256 ASCII bytes exceeds the 255-byte requestId ceiling.
        #expect(throws: FileTransferFrameCodec.EncodeError.requestIdTooLong(256)) {
            try FileTransferFrameCodec.encode(
                .chunk(requestId: String(repeating: "x", count: 256), payload: Data()))
        }
        // 100 × 4-byte scalars = 400 UTF-8 bytes.
        #expect(throws: FileTransferFrameCodec.EncodeError.requestIdTooLong(400)) {
            try FileTransferFrameCodec.encode(
                .end(requestId: String(repeating: "🦀", count: 100)))
        }
        // Metadata above the uint16 ceiling throws instead of truncating.
        let big = FileBeginMetadata(
            mime: "text/plain", size: 1, encoding: .binary,
            modifiedAt: "2026-11-09T00:00:00.000Z", fileName: String(repeating: "n", count: 70_000))
        #expect(throws: FileTransferFrameCodec.EncodeError.self) {
            try FileTransferFrameCodec.encode(.begin(requestId: "id", metadata: big))
        }
    }

    @Test func unknownEncodingRoundTrips() throws {
        let metadata = FileBeginMetadata(
            mime: "application/weird", size: 3, encoding: .unknown("base85"),
            modifiedAt: "2026-11-09T00:00:00.000Z")
        let encoded = try FileTransferFrameCodec.encode(
            .begin(requestId: "r", metadata: metadata))
        guard case .begin(_, let decoded)? = FileTransferFrameCodec.decode(encoded) else {
            Issue.record("frame did not decode")
            return
        }
        #expect(decoded.encoding == .unknown("base85"))
    }

    @Test func fileUploadRequestCarriesNoBytes() throws {
        let request = FileUploadRequest(
            fileName: "a.txt", mimeType: "text/plain", size: 3,
            modifiedAt: "2026-11-09T00:00:00.000Z")
        let data = try JSONEncoder().encode(SessionRequestEnvelope(request))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let message = try #require(json["message"] as? [String: Any])
        #expect(message["type"] as? String == "file.upload.request")
        #expect(message["fileName"] as? String == "a.txt")
        #expect(message["mimeType"] as? String == "text/plain")
        #expect(message["size"] as? Int == 3)
        #expect(message["modifiedAt"] as? String == "2026-11-09T00:00:00.000Z")
        #expect(!message.keys.contains("data") && !message.keys.contains("bytes"))
    }
}
