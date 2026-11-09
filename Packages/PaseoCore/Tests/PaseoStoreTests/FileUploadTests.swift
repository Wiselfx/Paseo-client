import Foundation
import PaseoFixtures
import PaseoKit
import PaseoProtocol
import Testing

@testable import PaseoStore

/// T14: the full upload flow driven by the fake — `file.upload.request`, then
/// `FileBegin`/`FileChunk…`/`FileEnd` binary frames correlated by `requestId`,
/// then the `uploaded_file` attachment fed back through T12's `sendWithAttachments`.
@Suite @MainActor
struct FileUploadTests {
    private func makeStore() -> (ConversationStore, FakeDaemonClient) {
        let client = FakeDaemonClient()
        client.onFetchAgents { _ in try Load.agents() }
        client.onFetchTimeline { _ in try Load.page() }
        client.onSetSubscription { _ in try Load.subscription() }
        return (ConversationStore(agentId: "agent-1", client: client), client)
    }

    private nonisolated static let uploadedFileJSON =
        """
        {"type":"uploaded_file","id":"upload_abc123","fileName":"note.txt","mimeType":"text/plain","size":11,"path":"/paseo-home/uploads/upload_abc123/note.txt"}
        """

    private var uploadedFile: AgentAttachment.UploadedFileAttachment {
        .init(
            id: "upload_abc123", fileName: "note.txt", mimeType: "text/plain", size: 11,
            path: "/paseo-home/uploads/upload_abc123/note.txt")
    }

    @Test func uploadStreamsBeginChunkEndAndReturnsTheAttachment() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            #expect(request.fileName == "note.txt")
            #expect(request.mimeType == "text/plain")
            #expect(request.size == 11)
            #expect(!request.modifiedAt.isEmpty)
            #expect(!request.requestId.isEmpty)
            return try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":\(Self.uploadedFileJSON),"error":null}
                    """.utf8))
        }

        let data = Data("hello world".utf8)
        let file = await store.upload(data: data, fileName: "note.txt", mimeType: "text/plain")

        #expect(file?.id == "upload_abc123")
        #expect(file?.size == 11)
        #expect(store.uploads.isUploading == false)
        #expect(store.uploads.progress == 1)
        #expect(store.uploads.bytesSent == 11)
        #expect(store.uploads.totalBytes == 11)
        #expect(store.uploads.error == nil)

        // Binary frames in order, all correlated to the JSON request's requestId.
        #expect(client.binaryMessages.count == 3)
        let request = try #require(client.requests(FileUploadRequest.self).first)
        let frames = try client.binaryMessages.map { try #require(FileTransferFrameCodec.decode($0)) }
        #expect(frames[0] == .begin(
            requestId: request.requestId,
            metadata: FileBeginMetadata(
                mime: "text/plain", size: 11, encoding: .binary,
                modifiedAt: request.modifiedAt, fileName: "note.txt")))
        #expect(frames[1] == .chunk(requestId: request.requestId, payload: data))
        #expect(frames[2] == .end(requestId: request.requestId))
    }

    @Test func chunksAreSizeBoundedAndReassemble() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":\(Self.uploadedFileJSON),"error":null}
                    """.utf8))
        }

        var pattern = Data()
        var seed: UInt8 = 7
        for _ in 0 ..< 300_000 {
            pattern.append(seed)
            seed = seed &* 31 &+ 11
        }
        let file = await store.upload(
            data: pattern, fileName: "blob.bin", mimeType: "application/octet-stream")
        #expect(file != nil)

        let request = try #require(client.requests(FileUploadRequest.self).first)
        let frames = try client.binaryMessages.map { try #require(FileTransferFrameCodec.decode($0)) }
        guard case .begin = frames.first else {
            Issue.record("expected .begin first")
            return
        }
        guard case .end = frames.last else {
            Issue.record("expected .end last")
            return
        }

        var reassembled = Data()
        for frame in frames {
            guard case .chunk(_, let payload) = frame else { continue }
            #expect(payload.count <= ConversationUpload.chunkSize)
            reassembled.append(payload)
        }
        #expect(reassembled == pattern)
        for frame in frames {
            guard case .chunk(let requestId, _) = frame else { continue }
            #expect(requestId == request.requestId)
        }
        #expect(store.uploads.totalBytes == pattern.count)
        #expect(store.uploads.bytesSent == pattern.count)
    }

    @Test func aFileOverTheLimitIsRefusedWithoutSendingAnything() async throws {
        let (store, _) = makeStore()
        let oversize = Data(count: ConversationUpload.maxBytes + 1)
        let file = await store.upload(
            data: oversize, fileName: "huge.bin", mimeType: "application/octet-stream")
        #expect(file == nil)
        #expect(store.uploads.error == "huge.bin is too large (50 MB max).")
        #expect(store.uploads.isUploading == false)
        #expect(store.uploads.progress == 0)
    }

    @Test func aDaemonSideErrorBecomesTheUploadError() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":null,"error":"Upload size mismatch: expected 11, received 4."}
                    """.utf8))
        }

        let file = await store.upload(
            data: Data("hello world".utf8), fileName: "note.txt", mimeType: "text/plain")
        #expect(file == nil)
        #expect(store.uploads.error == "Upload size mismatch: expected 11, received 4.")
        #expect(store.uploads.progress == 1) // frames did stream; the daemon rejected the result
        #expect(client.binaryMessages.count == 3)
    }

    @Test func cancelStopsTheStreamAndSendsNoChunks() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":\(Self.uploadedFileJSON),"error":null}
                    """.utf8))
        }
        // Hold the first binary frame (the begin) until the test sets the cancel flag.
        let gate = Gate()
        client.onBinarySend = { _ in await gate.wait() }

        let upload = Task {
            await store.upload(
                data: Data(count: 300_000), fileName: "blob.bin",
                mimeType: "application/octet-stream")
        }
        #expect(await eventually { store.uploads.isUploading })
        store.uploads.cancel()
        await gate.open()
        let result = await upload.value

        #expect(result == nil)
        #expect(store.uploads.error == "Upload canceled.")
        // Only the begin frame was sent; no chunks, no end.
        #expect(client.binaryMessages.count == 1)
        #expect(!store.uploads.isUploading)
        guard let sent = client.binaryMessages.first else { return }
        guard case .begin(_, let metadata)? = FileTransferFrameCodec.decode(sent) else {
            Issue.record("expected .begin, got \(String(describing: FileTransferFrameCodec.decode(sent)))")
            return
        }
        #expect(metadata.fileName == "blob.bin")
    }

    @Test func aSecondUploadIsRejectedWhileOneIsInFlight() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":\(Self.uploadedFileJSON),"error":null}
                    """.utf8))
        }
        let gate = Gate()
        client.onBinarySend = { _ in await gate.wait() }

        let running = Task {
            await store.upload(
                data: Data("hello world".utf8), fileName: "note.txt", mimeType: "text/plain")
        }
        #expect(await eventually { store.uploads.isUploading })

        let second = await store.upload(
            data: Data("hello".utf8), fileName: "second.txt", mimeType: "text/plain")
        #expect(second == nil)
        #expect(store.uploads.error == "An upload is already in flight.")

        await gate.open()
        let first = await running.value
        #expect(first?.id == "upload_abc123")
    }

    @Test func theUploadedFileRidesOnTheNextMessageThroughSendWithAttachments() async throws {
        let (store, client) = makeStore()
        client.onSend(FileUploadRequest.self) { request in
            try JSONDecoder().decode(
                FileUploadRequest.Response.self,
                from: Data(
                    """
                    {"requestId":"\(request.requestId)","file":\(Self.uploadedFileJSON),"error":null}
                    """.utf8))
        }
        client.onSendMessage { _ in try Load.sendMessage() }

        let file = await store.upload(
            data: Data("hello world".utf8), fileName: "note.txt", mimeType: "text/plain")
        let attachment = try #require(file)
        await store.sendWithAttachments("see attached", attachments: [.uploadedFile(attachment)])

        let sent = try #require(client.requests(SendAgentMessageRequest.self).first)
        #expect(sent.attachments?.count == 1)
        #expect(sent.attachments?.first?.type == "uploaded_file")
        #expect(sent.attachments?.first?.uploadedFile?.id == "upload_abc123")
        #expect(sent.attachments?.first?.uploadedFile?.path == attachment.path)
        #expect(store.actionError == nil)
    }
}
