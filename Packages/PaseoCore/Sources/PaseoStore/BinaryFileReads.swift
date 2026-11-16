import Foundation
import PaseoProtocol

/// Assembles the daemon's streamed file reads.
///
/// `file_explorer_request` mode `file` answers inline (base64) only for images. With
/// `acceptBinary: true` on a session that has a binary channel, the daemon streams the file as
/// `FileBegin` / `FileChunk…` / `FileEnd` frames correlated by `requestId` and sends **no** JSON
/// response (`workspace-files-session.ts:298-331`); the connection closes the request itself at
/// `FileEnd` (`DaemonConnection.completeFileRead`). The store pre-registers the id, sends, and
/// asks this actor for the assembled bytes once that close arrives.
///
/// Upstream: `packages/client/src/daemon-client.ts:5635` (`readFile`: pending/completed maps),
/// `:7581` (`handleFileTransferFrame`), `packages/server/src/server/session/files/workspace-files-session.ts:298`.
///
/// Everything here runs on the actor, never on the main actor; a chunk is appended in place, and
/// the buffer never grows past the read's `maxBytes`, so a huge file is never held twice.
actor BinaryFileReads {
    /// The bytes and metadata of one finished transfer (`FileReadResult`, `daemon-client.ts:604`).
    struct Assembly: Sendable, Equatable {
        var data: Data
        var mimeType: String
        var size: Int
        var modifiedAt: String
        var revision: String?
    }

    /// Why a registered read produced no bytes. `.tooLarge` matches the daemon's own refusal text
    /// at the store boundary (`File is too large to display`).
    enum Failure: Error, Sendable, Equatable {
        case tooLarge
        case incomplete(expected: Int, received: Int)
        case timedOut
    }

    /// How long a read waits for the tail of a transfer *after* the request was closed. The daemon
    /// emits every frame before its `FileEnd`, so only already-received frames are drained here; a
    /// short or lost frame fails honestly instead of hanging.
    static let assemblyDeadline = Duration.seconds(10)

    private struct Transfer {
        var maxBytes: Int
        var mimeType: String
        var size: Int
        var modifiedAt: String
        var revision: String?
        var buffer: Data
        /// Old daemons stream despite `maxBytes` (`daemon-client.ts:7595-7635`). Their chunks are
        /// dropped as they arrive and the read fails `.tooLarge` at `FileEnd`.
        var isDiscarded: Bool
    }

    private struct Pending {
        var maxBytes: Int
        var transfer: Transfer?
        var outcome: Result<Assembly, Failure>?
        var waiter: CheckedContinuation<Assembly, any Error>?
        /// Armed by `result(for:)`: bounds the wait for a `FileEnd` that never comes.
        var watchdog: Task<Void, Never>?
    }

    private var pending: [String: Pending] = [:]

    // MARK: Driver side

    /// Registers the id a read is about to use. Must happen before the request frame is written,
    /// so the very first `FileBegin` is never missed.
    func register(requestId: String, maxBytes: Int) {
        guard pending[requestId] == nil else { return }
        pending[requestId] = Pending(
            maxBytes: max(maxBytes, 1), transfer: nil, outcome: nil, waiter: nil, watchdog: nil)
    }

    /// One inbound WebSocket binary frame. Decoded only when it carries a file-transfer opcode
    /// (`0x10…0x12`); terminal (`0x01…0x08`) and diff (`0x40…0x4f`) frames are left untouched.
    func handle(binaryFrame data: Data) {
        guard let opcode = data.first,
            opcode == FileTransferOpcode.fileBegin.rawValue
                || opcode == FileTransferOpcode.fileChunk.rawValue
                || opcode == FileTransferOpcode.fileEnd.rawValue
        else { return }
        guard let frame = FileTransferFrameCodec.decode(data) else { return }

        switch frame {
        case .begin(let requestId, let metadata):
            begin(requestId, metadata)

        case .chunk(let requestId, let payload):
            append(payload, to: requestId)

        case .end(let requestId):
            finish(requestId)
        }
    }

    private func begin(_ requestId: String, _ metadata: FileBeginMetadata) {
        guard var entry = pending[requestId], entry.outcome == nil else { return }
        let cap = entry.maxBytes
        let isDiscarded = metadata.size > cap
        var buffer = Data()
        // Reserve once, up front, and only for a size the cap already accepts: the assembled
        // `Data` is then written in place with no growth copy.
        if !isDiscarded { buffer.reserveCapacity(metadata.size) }
        entry.transfer = Transfer(
            maxBytes: cap, mimeType: metadata.mime, size: metadata.size,
            modifiedAt: metadata.modifiedAt, revision: metadata.revision,
            buffer: buffer, isDiscarded: isDiscarded)
        pending[requestId] = entry
    }

    private func append(_ payload: Data, to requestId: String) {
        guard var entry = pending[requestId], entry.outcome == nil, var transfer = entry.transfer,
            !transfer.isDiscarded
        else { return }
        guard transfer.buffer.count + payload.count <= transfer.maxBytes else {
            // Never hold more than the cap, whatever the daemon does.
            transfer.isDiscarded = true
            transfer.buffer = Data()
            entry.transfer = transfer
            pending[requestId] = entry
            return
        }
        transfer.buffer.append(payload)
        entry.transfer = transfer
        pending[requestId] = entry
    }

    private func finish(_ requestId: String) {
        guard var entry = pending[requestId], entry.outcome == nil else { return }
        let outcome: Result<Assembly, Failure>
        if let transfer = entry.transfer {
            if transfer.isDiscarded || transfer.size > transfer.maxBytes {
                outcome = .failure(.tooLarge)
            } else if transfer.buffer.count != transfer.size {
                outcome = .failure(
                    .incomplete(expected: transfer.size, received: transfer.buffer.count))
            } else {
                outcome = .success(
                    Assembly(
                        data: transfer.buffer, mimeType: transfer.mimeType,
                        size: transfer.size, modifiedAt: transfer.modifiedAt,
                        revision: transfer.revision))
            }
        } else {
            // `FileEnd` with no `FileBegin`: there is nothing to hand back.
            outcome = .failure(.incomplete(expected: 0, received: 0))
        }
        entry.transfer = nil
        entry.outcome = outcome
        settle(entry, for: requestId)
    }

    // MARK: Reader side

    /// Waits for the transfer to finish. Called after the request was closed (the `FileEnd` was
    /// received), so this only waits for the event loop to hand the frames over.
    func result(for requestId: String, deadline: Duration = assemblyDeadline) async throws
        -> Assembly
    {
        if let outcome = pending[requestId]?.outcome {
            take(requestId)
            return try outcome.get()
        }
        guard pending[requestId] != nil else {
            throw Failure.incomplete(expected: 0, received: 0)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Assembly, any Error>) in
                // The closure runs synchronously inside the actor: no frame can slip between the
                // re-check and storing the waiter.
                if let outcome = pending[requestId]?.outcome {
                    take(requestId)
                    continuation.resume(with: outcome)
                    return
                }
                guard pending[requestId] != nil else {
                    continuation.resume(throwing: Failure.incomplete(expected: 0, received: 0))
                    return
                }
                pending[requestId]?.waiter = continuation
                pending[requestId]?.watchdog = Task { [weak self] in
                    do {
                        try await Task.sleep(for: deadline)
                    } catch {
                        return
                    }
                    await self?.expire(requestId)
                }
            }
        } onCancel: {
            Task { await self.abandon(requestId: requestId) }
        }
    }

    /// Forgets a read: the response carried an error, the daemon answered the legacy JSON shape,
    /// or the caller was cancelled. Later frames for the id are ignored.
    func abandon(requestId: String) {
        guard let entry = pending.removeValue(forKey: requestId) else { return }
        entry.watchdog?.cancel()
        entry.waiter?.resume(throwing: CancellationError())
    }

    /// What the broker still holds, for tests and for the store's leak-free paths.
    var pendingCount: Int { pending.count }

    // MARK: Resolution

    private func expire(_ requestId: String) {
        guard var entry = pending[requestId], entry.outcome == nil else { return }
        entry.outcome = .failure(.timedOut)
        settle(entry, for: requestId)
    }

    /// Hands the outcome to the waiter (or keeps it until `result` asks). The entry is done once
    /// it is handed over; `take` removes it.
    private func settle(_ entry: Pending, for requestId: String) {
        guard let waiter = entry.waiter else {
            // Nobody asked yet (frames arrive before the response): keep the outcome.
            pending[requestId] = entry
            return
        }
        let outcome = entry.outcome ?? .failure(.timedOut)
        take(requestId)
        waiter.resume(with: outcome)
    }

    private func take(_ requestId: String) {
        pending.removeValue(forKey: requestId)?.watchdog?.cancel()
    }
}
