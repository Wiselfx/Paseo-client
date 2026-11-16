import Foundation

/// File-transfer frames produced by the *upstream* codec (`packages/protocol/src/binary-frames/
/// file-transfer.ts`); see `Tools/capture-file-transfer.mjs`. Never hand-edit `frames.json`.
/// The metadata is redeclared locally because PaseoFixtures depends on nothing; tests map it onto
/// the protocol types themselves.
public struct FileUploadFrameFixture: Decodable, Sendable {
    public let name: String
    public let opcode: UInt8
    public let requestId: String
    public let metadata: FileUploadMetadataFixture?
    public let payloadBase64: String?
    public let encodedBase64: String

    public var encoded: Data { Data(base64Encoded: encodedBase64) ?? Data() }
    public var payload: Data? { payloadBase64.map { Data(base64Encoded: $0) ?? Data() } }
}

/// The `FileBeginMetadataSchema` shape, as decoded from the fixture manifest.
public struct FileUploadMetadataFixture: Decodable, Sendable, Equatable {
    public let mime: String
    public let size: Int
    public let encoding: String
    public let modifiedAt: String
    public let revision: String?
    public let fileName: String?
}

private struct FileUploadFramesManifest: Decodable {
    let frames: [FileUploadFrameFixture]
}

extension Fixture {
    /// The upstream-produced golden frames for `FileTransferFrameCodec`.
    public static func fileUploadFrames() throws -> [FileUploadFrameFixture] {
        try JSONDecoder().decode(
            FileUploadFramesManifest.self, from: data("frames", area: "file-upload")
        ).frames
    }
}
