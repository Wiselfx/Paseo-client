import Foundation
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// The byte layout helpers for both suites: the same frames the daemon streams for a read.
private enum Frames {
    static func begin(
        _ requestId: String, size: Int, mime: String = "video/mp4",
        revision: String? = "rev-1"
    ) throws -> Data {
        try FileTransferFrameCodec.encode(
            .begin(
                requestId: requestId,
                metadata: FileBeginMetadata(
                    mime: mime, size: size, encoding: .binary,
                    modifiedAt: "2026-11-15T12:00:00.000Z", revision: revision)))
    }

    static func chunk(_ requestId: String, _ payload: Data) throws -> Data {
        try FileTransferFrameCodec.encode(.chunk(requestId: requestId, payload: payload))
    }

    static func end(_ requestId: String) throws -> Data {
        try FileTransferFrameCodec.encode(.end(requestId: requestId))
    }
}

/// V3: `FileBegin` / `FileChunk…` / `FileEnd`, correlated by request id, assembled off the main
/// actor. Upstream: `packages/client/src/daemon-client.ts:7581` (`handleFileTransferFrame`).
@Suite struct BinaryFileReadsTests {
    @Test func assemblesInterleavedTransfersByRequestId() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "one", maxBytes: 1 << 20)
        await reads.register(requestId: "two", maxBytes: 1 << 20)

        // Two files in flight at once: their frames interleave, and one ends before the other.
        await reads.handle(binaryFrame: try Frames.begin("one", size: 6))
        await reads.handle(binaryFrame: try Frames.begin("two", size: 5))
        await reads.handle(binaryFrame: try Frames.chunk("one", Data("abc".utf8)))
        await reads.handle(binaryFrame: try Frames.chunk("two", Data("12".utf8)))
        await reads.handle(binaryFrame: try Frames.chunk("one", Data("def".utf8)))
        await reads.handle(binaryFrame: try Frames.chunk("two", Data("345".utf8)))
        await reads.handle(binaryFrame: try Frames.end("two"))
        await reads.handle(binaryFrame: try Frames.end("one"))

        let two = try await reads.result(for: "two")
        let one = try await reads.result(for: "one")

        #expect(one.data == Data("abcdef".utf8))
        #expect(one.size == 6)
        #expect(two.data == Data("12345".utf8))
        #expect(two.size == 5)
        #expect(await reads.pendingCount == 0)
    }

    @Test func metadataTravelsWithTheBytes() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "clip", maxBytes: 1 << 20)
        await reads.handle(
            binaryFrame: try Frames.begin("clip", size: 4, mime: "audio/wav", revision: "rev-7"))
        await reads.handle(binaryFrame: try Frames.chunk("clip", Data([0x52, 0x49, 0x46, 0x46])))
        await reads.handle(binaryFrame: try Frames.end("clip"))

        let assembled = try await reads.result(for: "clip")
        #expect(assembled.data == Data([0x52, 0x49, 0x46, 0x46]))
        #expect(assembled.mimeType == "audio/wav")
        #expect(assembled.revision == "rev-7")
        #expect(assembled.modifiedAt == "2026-11-15T12:00:00.000Z")
    }

    @Test func chunksBeforeBeginAreIgnored() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "late", maxBytes: 1024)
        await reads.handle(binaryFrame: try Frames.chunk("late", Data("ghost".utf8)))
        await reads.handle(binaryFrame: try Frames.begin("late", size: 2))
        await reads.handle(binaryFrame: try Frames.chunk("late", Data("ok".utf8)))
        await reads.handle(binaryFrame: try Frames.end("late"))

        #expect(try await reads.result(for: "late").data == Data("ok".utf8))
    }

    @Test func anEndShortOfTheAdvertisedSizeFailsInsteadOfReturningPartialBytes() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "short", maxBytes: 1024)
        await reads.handle(binaryFrame: try Frames.begin("short", size: 8))
        await reads.handle(binaryFrame: try Frames.chunk("short", Data("four".utf8)))
        await reads.handle(binaryFrame: try Frames.end("short"))

        await #expect(throws: BinaryFileReads.Failure.incomplete(expected: 8, received: 4)) {
            _ = try await reads.result(for: "short")
        }
        #expect(await reads.pendingCount == 0)
    }

    @Test func aMissingEndFailsAtTheAssemblyDeadline() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "cut", maxBytes: 1024)
        await reads.handle(binaryFrame: try Frames.begin("cut", size: 4))
        await reads.handle(binaryFrame: try Frames.chunk("cut", Data("half".utf8)))

        await #expect(throws: BinaryFileReads.Failure.timedOut) {
            _ = try await reads.result(for: "cut", deadline: .milliseconds(40))
        }
        #expect(await reads.pendingCount == 0)
    }

    @Test func aFileOverTheCapIsNeverBuffered() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "big", maxBytes: 4)
        await reads.handle(binaryFrame: try Frames.begin("big", size: 9))
        await reads.handle(binaryFrame: try Frames.chunk("big", Data("1234".utf8)))
        await reads.handle(binaryFrame: try Frames.chunk("big", Data("5678".utf8)))
        await reads.handle(binaryFrame: try Frames.end("big"))

        await #expect(throws: BinaryFileReads.Failure.tooLarge) {
            _ = try await reads.result(for: "big")
        }
    }

    @Test func aChunkPastTheCapDiscardsTheWholeTransfer() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "liar", maxBytes: 4)
        // The advertised size fits, the bytes do not: the buffer stops growing at the cap.
        await reads.handle(binaryFrame: try Frames.begin("liar", size: 4))
        await reads.handle(binaryFrame: try Frames.chunk("liar", Data("12345678".utf8)))
        await reads.handle(binaryFrame: try Frames.end("liar"))

        await #expect(throws: BinaryFileReads.Failure.tooLarge) {
            _ = try await reads.result(for: "liar")
        }
    }

    @Test func framesForAnUnregisteredRequestAreIgnored() async throws {
        let reads = BinaryFileReads()
        await reads.handle(binaryFrame: try Frames.begin("stranger", size: 2))
        await reads.handle(binaryFrame: try Frames.chunk("stranger", Data("hi".utf8)))
        await reads.handle(binaryFrame: try Frames.end("stranger"))
        #expect(await reads.pendingCount == 0)
    }

    @Test func terminalAndDiffFramesAreLeftToTheirOwnStores() async throws {
        let reads = BinaryFileReads()
        await reads.register(requestId: "open", maxBytes: 1024)
        // Opcode 0x01 is terminal output; 0x40 is a diff frame. Neither is file transfer.
        await reads.handle(binaryFrame: Data([0x01, 0x00, 0x41, 0x42]))
        await reads.handle(binaryFrame: Data([0x40, 0x00, 0x01]))
        #expect(await reads.pendingCount == 1)
    }
}

/// V3: `WorkspaceFiles.fetchBytes` rides the binary channel and falls back to the inline JSON
/// read for images and transports without one.
@Suite @MainActor
struct WorkspaceFilesBinaryReadTests {
    private nonisolated static func binaryResponse(
        for request: FileExplorerRequest
    ) -> FileExplorerRequest.Response {
        FileExplorerRequest.Response(
            requestId: request.requestId, cwd: request.cwd, path: request.path ?? "",
            mode: .file, directory: nil, file: nil, error: nil)
    }

    @Test func fetchBytesStreamsTheFileThroughTheBinaryChannel() async throws {
        let client = FakeDaemonClient()
        let reads = BinaryFileReads()
        let payload = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        client.on(FileExplorerRequest.self) { request in
            #expect(request.acceptBinary == true)
            #expect(request.maxBytes == 4096)
            #expect(!request.requestId.isEmpty)
            // The daemon streams before it answers; the event loop hands the frames over after
            // the request waiter resumes, so they land in their own task.
            let requestId = request.requestId
            let begin = try FileTransferFrameCodec.encode(
                .begin(
                    requestId: requestId,
                    metadata: FileBeginMetadata(
                        mime: "video/mp4", size: payload.count, encoding: .binary,
                        modifiedAt: "2026-11-15T12:00:00.000Z", revision: "rev-9")))
            let chunk = try FileTransferFrameCodec.encode(
                .chunk(requestId: requestId, payload: payload))
            let end = try FileTransferFrameCodec.encode(.end(requestId: requestId))
            Task {
                await reads.handle(binaryFrame: begin)
                await reads.handle(binaryFrame: chunk)
                await reads.handle(binaryFrame: end)
            }
            return Self.binaryResponse(for: request)
        }

        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: reads)
        let result = try await files.fetchBytes("clip.mp4", maxBytes: 4096)

        #expect(result.path == "clip.mp4")
        #expect(result.data == payload)
        #expect(result.size == payload.count)
        #expect(result.mimeType == "video/mp4")
        #expect(result.revision == "rev-9")
        #expect(result.kind == .binary)

        // The read is side-effect free, like `fetch`.
        #expect(files.file == nil)
        #expect(files.phase == .idle)
        #expect(files.error == nil)
        #expect(await reads.pendingCount == 0)
    }

    @Test func fetchBytesFallsBackToTheJSONRoadWithoutABinaryChannel() async throws {
        let client = FakeDaemonClient()
        client.setCanReceiveBinaryFrames(false)
        client.on(FileExplorerRequest.self) { request in
            #expect(request.acceptBinary == nil)
            return try Load.fileRead()
        }

        let fixture = try Load.fileRead()
        let expected = Data((try #require(fixture.file).textContent ?? "").utf8)

        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: BinaryFileReads())
        let result = try await files.fetchBytes("convert.py")

        #expect(result.path == "convert.py")
        #expect(result.kind == .text)
        #expect(result.data == expected)
        #expect(!result.data.isEmpty)
    }

    @Test func fetchBytesKeepsImagesOnTheJSONRoad() async throws {
        let client = FakeDaemonClient()
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        client.on(FileExplorerRequest.self) { request in
            #expect(request.acceptBinary == nil)
            var response = try Load.fileRead()
            var file = try #require(response.file)
            file.path = request.path ?? ""
            file.kind = .image
            file.encoding = .base64
            file.content = png.base64EncodedString()
            response.file = file
            response.path = file.path
            return response
        }

        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: BinaryFileReads())
        let result = try await files.fetchBytes("red.png")

        #expect(result.data == png)
        #expect(result.kind == .image)
    }

    @Test func aRefusedReadThrowsTheDaemonsTextAndDropsThePendingRead() async throws {
        let client = FakeDaemonClient()
        let reads = BinaryFileReads()
        client.on(FileExplorerRequest.self) { request in
            var response = Self.binaryResponse(for: request)
            response.error = "File is too large to display"
            return response
        }
        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: reads)

        await #expect(
            throws: PaseoStoreError.missingFile(
                path: "clip.mp4", message: "File is too large to display")
        ) {
            _ = try await files.fetchBytes("clip.mp4", maxBytes: 4096)
        }
        #expect(await reads.pendingCount == 0)

        // A frame that still arrives for the abandoned id has nowhere to go.
        let requestId = try #require(client.requests(FileExplorerRequest.self).last?.requestId)
        await reads.handle(binaryFrame: try Frames.begin(requestId, size: 4))
        #expect(await reads.pendingCount == 0)
    }

    @Test func aStreamedFilePastTheCapReadsAsTheDaemonsRefusal() async throws {
        let client = FakeDaemonClient()
        let reads = BinaryFileReads()
        client.on(FileExplorerRequest.self) { request in
            // An old daemon that streams despite `maxBytes`.
            let requestId = request.requestId
            let begin = try FileTransferFrameCodec.encode(
                .begin(
                    requestId: requestId,
                    metadata: FileBeginMetadata(
                        mime: "video/mp4", size: 8, encoding: .binary,
                        modifiedAt: "2026-11-15T12:00:00.000Z")))
            let chunk = try FileTransferFrameCodec.encode(
                .chunk(requestId: requestId, payload: Data(repeating: 0, count: 8)))
            let end = try FileTransferFrameCodec.encode(.end(requestId: requestId))
            Task {
                await reads.handle(binaryFrame: begin)
                await reads.handle(binaryFrame: chunk)
                await reads.handle(binaryFrame: end)
            }
            return Self.binaryResponse(for: request)
        }
        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: reads)

        await #expect(
            throws: PaseoStoreError.missingFile(
                path: "clip.mp4", message: "File is too large to display")
        ) {
            _ = try await files.fetchBytes("clip.mp4", maxBytes: 4)
        }
        #expect(await reads.pendingCount == 0)
    }

    @Test func aTransferThatEndsShortReportsAnIncompleteRead() async throws {
        let client = FakeDaemonClient()
        let reads = BinaryFileReads()
        client.on(FileExplorerRequest.self) { request in
            let requestId = request.requestId
            let begin = try FileTransferFrameCodec.encode(
                .begin(
                    requestId: requestId,
                    metadata: FileBeginMetadata(
                        mime: "audio/wav", size: 8, encoding: .binary,
                        modifiedAt: "2026-11-15T12:00:00.000Z")))
            let end = try FileTransferFrameCodec.encode(.end(requestId: requestId))
            Task {
                await reads.handle(binaryFrame: begin)
                await reads.handle(binaryFrame: end)
            }
            return Self.binaryResponse(for: request)
        }
        let files = WorkspaceFiles(
            cwd: "/tmp/fixture-sandbox", client: client, binaryFileReads: reads)

        await #expect(throws: PaseoStoreError.transferIncomplete(path: "tone.wav")) {
            _ = try await files.fetchBytes("tone.wav")
        }
        #expect(await reads.pendingCount == 0)
    }
}
