import Foundation
import Observation
import PaseoKit
import PaseoProtocol

// T14: `file.upload.request` + `FileBegin`/`FileChunk`/`FileEnd` binary frames. The JSON request
// carries no bytes; the stream bypasses the send queue and is correlated by `requestId`.
// Source: packages/protocol/src/binary-frames/file-transfer.ts; upstream client drive:
// packages/client/src/daemon-client.ts `uploadFile` (:5628-5714).

/// Per-conversation file upload state: one upload at a time, progress observable, cancellable.
@MainActor @Observable
public final class ConversationUpload {
    /// The app-side pre-check (`FILE_UPLOAD_MAX_BYTES`, `app/attachments/upload-limit.ts:1`).
    /// The daemon enforces its own limits afterwards; this spares the wire call for files it
    /// would reject anyway.
    public static let maxBytes = 50 * 1024 * 1024
    /// Client-side chunk size; upstream sends the same (`chunkSize ?? 128 * 1024`).
    static let chunkSize = 128 * 1024
    /// R18 item 6: the relay caps a plaintext frame at ~25 MB (32 MiB on the wire), so on a
    /// relay connection an upload chunk is capped at one Noise record's data — it can never
    /// trip `frameTooLarge` no matter how large the file is. Direct keeps upstream's size.
    static func chunkSize(relay: Bool) -> Int {
        relay ? min(chunkSize, RelayRecordCodec.maxChunkDataBytes) : chunkSize
    }

    /// True when this upload rides a protected relay channel (set by HostSession from the
    /// endpoint; previews and tests leave it false).
    var isRelayConnection = false

    public private(set) var isUploading = false
    /// Name of the file in flight (or of the last completed upload).
    public private(set) var fileName: String?
    public private(set) var bytesSent = 0
    public private(set) var totalBytes = 0
    /// 0…1. Fraction of bytes written to the socket; reaches 1 when the file is fully sent.
    public private(set) var progress: Double = 0
    /// What went wrong with the last attempt, if anything. Cleared on the next attempt.
    public private(set) var error: String?
    /// The attachment from the last completed upload, for one-off inspection.
    public private(set) var lastUploaded: AgentAttachment.UploadedFileAttachment?

    private let client: (any DaemonClient)?
    private var cancelRequested = false

    init(client: (any DaemonClient)?) {
        self.client = client
    }

    /// Streams `data` to the daemon. On success, returns the attachment to pass to
    /// `sendWithAttachments`; on failure or cancellation, returns `nil` and sets `error`.
    public func upload(data: Data, fileName: String, mimeType: String) async -> AgentAttachment.UploadedFileAttachment? {
        guard !isUploading else {
            error = "An upload is already in flight."
            return nil
        }
        guard let client else {
            error = "Not connected to a daemon."
            return nil
        }
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "The file needs a name."
            return nil
        }
        guard !mimeType.isEmpty else {
            error = "The file needs a MIME type."
            return nil
        }
        guard data.count <= Self.maxBytes else {
            error = "\(name) is too large (50 MB max)."
            return nil
        }

        cancelRequested = false
        isUploading = true
        self.fileName = name
        bytesSent = 0
        totalBytes = data.count
        progress = 0
        error = nil
        lastUploaded = nil

        let modifiedAt = Self.iso8601Now()

        let request = FileUploadRequest(
            fileName: name, mimeType: mimeType, size: data.count, modifiedAt: modifiedAt)

        // The daemon answers only after every byte is in and the file is on disk, so initiate
        // first (inline — the frame is on the socket when this returns), stream the correlated
        // binary frames, then await the response at the end.
        let initiated: InitiatedResponse<FileUploadRequest>
        do {
            initiated = try await client.initiate(request, timeout: .seconds(120))
        } catch {
            self.error = uploadErrorText(error)
            finish()
            return nil
        }
        let requestId = initiated.requestId

        do {
            try await send(
                .begin(
                    requestId: requestId,
                    metadata: FileBeginMetadata(
                        mime: mimeType, size: data.count, encoding: .binary,
                        modifiedAt: modifiedAt, fileName: name)))
            var offset = 0
            let chunkBytes = Self.chunkSize(relay: isRelayConnection)
            while offset < data.count {
                if cancelRequested { return abortUpload() }
                let end = min(offset + chunkBytes, data.count)
                try await send(
                    .chunk(requestId: requestId, payload: Data(data[offset ..< end])))
                offset = end
                bytesSent = end
                progress = totalBytes == 0 ? 1 : Double(bytesSent) / Double(totalBytes)
                // Give the runloop and cancellation a chance between bounded pieces.
                await Task.yield()
            }
            if cancelRequested { return abortUpload() }
            try await send(.end(requestId: requestId))
            progress = 1
        } catch {
            self.error = uploadErrorText(error)
            finish()
            return nil
        }

        do {
            let response = try await initiated.value()
            if let daemonError = response.error {
                self.error = daemonError
                finish()
                return nil
            }
            guard let file = response.file else {
                self.error = "The daemon did not return a file."
                finish()
                return nil
            }
            lastUploaded = file
            finish()
            return file
        } catch {
            self.error = uploadErrorText(error)
            finish()
            return nil
        }
    }

    /// Cancels the in-flight upload, if any. No frames are sent after this returns; the daemon-side
    /// partial upload is abandoned (it stays in the daemon's `paseoHome/uploads/` until its stale
    /// timeout reclaims it — there is no upstream cancel frame).
    public func cancel() {
        cancelRequested = true
    }

    private func send(_ frame: FileTransferFrame) async throws {
        let packed = try FileTransferFrameCodec.encode(frame)
        guard let client else { throw ConnectionError.disconnected }
        try await client.send(binary: packed)
    }

    private func abortUpload() -> AgentAttachment.UploadedFileAttachment? {
        error = "Upload canceled."
        finish()
        return nil
    }

    private func finish() {
        isUploading = false
        cancelRequested = false
    }

    private func uploadErrorText(_ error: Error) -> String {
        switch error {
        case ConnectionError.disconnected: "Lost the connection to the daemon mid-upload."
        case ConnectionError.timeout: "The daemon did not answer the upload in time."
        case ConnectionError.protocolViolation(let message): "Upload frame rejected: \(message)"
        case FileTransferFrameCodec.EncodeError.requestIdEmpty: "Internal error: empty request id."
        case let FileTransferFrameCodec.EncodeError.requestIdTooLong(count): "Internal error: request id too long (\(count) bytes)."
        case let FileTransferFrameCodec.EncodeError.metadataTooLong(count): "The file name is too long (\(count) bytes of metadata)."
        default: String(describing: error)
        }
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

extension ConversationStore {
    /// Streams `data` to the daemon and returns the uploaded-file attachment, or `nil` on
    /// failure/cancel. Attach the result with `sendWithAttachments(_:attachments:)`.
    public func upload(data: Data, fileName: String, mimeType: String) async -> AgentAttachment.UploadedFileAttachment? {
        await uploads.upload(data: data, fileName: fileName, mimeType: mimeType)
    }

    /// Cancels the in-flight upload, if any.
    public func cancelUpload() {
        uploads.cancel()
    }
}
