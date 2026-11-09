import Crypto
import Foundation
import Synchronization

// The relay socket: a `WebSocketTransport` that speaks the protected E2EE channel before any
// application frame, then behaves exactly like a direct socket.
// Spec: docs/research/11-relay-pairing.md §4.3-§4.5, §5; ticket docs/tickets/R17-relay-transport.md.
//
//   client                                   daemon
//     | -- e2ee_hello (msg1, repeated 1/s) --> |
//     | <------- e2ee_ready (msg2) ----------- |
//     | ========= protected records ========== |   kind/flags/length inside the ciphertext
//
// Only protected mode exists here. A daemon that answers with a legacy ready, or with a ready that
// does not authenticate, is a failed handshake: close 4002 and never retry on this channel.

/// Client-side close codes. A browser `WebSocket.close` accepts only 1000 or 3000-4999, and
/// URLSession has the same restriction in practice, so the client never sends 1008/1011.
public enum RelayCloseCode {
    /// The socket went away before the protected channel opened. Retryable: the relay or the
    /// daemon may simply be restarting.
    public static let neverOpened = 4001
    /// Protected handshake failed, or the daemon offered only legacy. Terminal: retrying against
    /// the same daemon cannot help.
    public static let protectedHandshakeFailed = 4002
    /// An inbound record failed authentication or framing. Terminal: either the peer or the relay
    /// is broken or tampering.
    public static let recordFailed = 4003

    /// The daemon's own codes. Both are usually replaced by the relay before a client sees them,
    /// so they only mean something on a same-host relay.
    public static let daemonProtectedRequired = 1008
    public static let daemonRecordFailure = 1011
}

/// What can go wrong before a frame reaches the wire. A frame that is too large is refused
/// without closing the socket: only the operation that asked for it should fail.
public enum RelayTransportError: Error, Sendable, Equatable {
    case frameTooLarge(wireBytes: Int, limit: Int)
}

/// A socket that is closed before it starts. Used when a relay link cannot be built (an invalid
/// key can only come from a hand-made `DaemonEndpoint`), so the failure surfaces as a close code
/// instead of a crash or a silent hang.
public struct ClosedTransport: WebSocketTransport, Sendable {
    public var closed: WebSocketClosed

    public init(closed: WebSocketClosed) {
        self.closed = closed
    }

    public func send(text: String) async throws { throw closed }
    public func send(binary: Data) async throws { throw closed }
    public func receive() async throws -> WebSocketFrame { throw closed }
    public func close(code: Int) {}
}

/// A protected relay socket over any base `WebSocketTransport`.
///
/// `WebSocketTransport` is request/next-frame; the E2EE channel is a state machine with timers. The
/// adapter is an `AsyncThrowingStream` of decrypted frames plus a mutex-guarded state:
///
/// | phase | `send` | inbound |
/// | --- | --- | --- |
/// | `handshaking` | queued (cap 200, oldest dropped) | only `e2ee_ready` is acted on |
/// | `flushing` | queued, drained by the flusher | records |
/// | `open` | encrypted and written | records |
/// | `closed` | throws `WebSocketClosed` | nothing |
public final class RelayWebSocketTransport: WebSocketTransport, RelaySecurityReporting,
    @unchecked Sendable
{
    public struct Configuration: Sendable {
        /// The hello is resent byte-for-byte this often until a ready arrives.
        public var handshakeRetryInterval: Duration = .seconds(1)
        /// No protection by now means the daemon is not answering: fail with 4002, do not hang.
        public var handshakeTimeout: Duration = .seconds(20)
        /// Frames queued while handshaking, as upstream buffers them. Older frames are dropped.
        public var maximumPendingSends = 200
        /// The relay's per-message limit: 32 MiB, versus 100 MiB on a direct socket.
        public var maximumWireBytes = 32 * 1024 * 1024
        public init() {}
    }

    // MARK: State

    private enum Phase {
        case handshaking
        /// Channel open; buffered frames are being written before anything newer.
        case flushing
        case open
        case closed
    }

    private struct Pending {
        var kind: RelayFrameKind
        var data: [UInt8]
    }

    private struct State {
        var phase: Phase = .handshaking
        var handshake: NoiseNK
        var helloText: String
        var sender: NoiseCipherState?
        var receiver: NoiseCipherState?
        var binaryCiphertext = true
        var pending: [Pending] = []
        var closeCode: Int?
        var closeReason = ""
        var finished = false
        var clock: Task<Void, Never>?
    }

    private enum Decision {
        case write([UInt8], asBinary: Bool)
        case queued
        case fail(WebSocketClosed)
        case tooLarge(Int)
    }

    private let base: any WebSocketTransport
    private let configuration: Configuration
    private let mutex: Mutex<State>
    /// `Failure` is `any Error` because only that form of `AsyncThrowingStream` exists here; the
    /// only error ever sent is `WebSocketClosed`.
    private let stream: AsyncThrowingStream<WebSocketFrame, any Error>
    private let continuation: AsyncThrowingStream<WebSocketFrame, any Error>.Continuation
    private let taskLock = Mutex<[Task<Void, Never>]>([])

    /// - Parameters:
    ///   - base: the socket pointed at the relay URL.
    ///   - link: daemon identity from the pairing offer. `minimumSecurityMode` is enforced here
    ///     too, so a legacy ready is refused even if a caller forgets to ask.
    public init(
        base: any WebSocketTransport,
        link: DaemonEndpoint.RelayLink,
        configuration: Configuration = Configuration()
    ) throws {
        self.base = base
        self.configuration = configuration

        var handshake = try NoiseNK(remoteStatic: link.daemonPublicKey, prologue: NoiseNK.prologue)
        let message1 = try handshake.writeMessage(
            payload: RelayHandshakeParameters(binaryCiphertext: true).encoded())

        // The legacy key in the hello envelope is what a pre-0.13 daemon would use. This client
        // never derives the legacy key; the field only has to parse for the daemon's validator.
        let legacyEphemeral = NoiseKeyPair.random()
        let helloText = Self.helloText(
            message1: message1, legacyPublicKey: legacyEphemeral.publicKey)

        var continuation: AsyncThrowingStream<WebSocketFrame, any Error>.Continuation?
        let stream = AsyncThrowingStream<WebSocketFrame, any Error>(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        guard let continuation else {
            throw WebSocketClosed(code: RelayCloseCode.neverOpened, reason: "no stream")
        }
        self.stream = stream
        self.continuation = continuation
        self.mutex = Mutex(State(handshake: handshake, helloText: helloText))

        start()
    }

    // MARK: Sending

    public func send(text: String) async throws {
        try await submit(.text, Array(text.utf8))
    }

    public func send(binary: Data) async throws {
        try await submit(.binary, Array(binary))
    }

    private func submit(_ kind: RelayFrameKind, _ frame: [UInt8]) async throws {
        let decision = mutex.withLock { state -> Decision in
            switch state.phase {
            case .closed:
                return .fail(
                    WebSocketClosed(code: state.closeCode ?? 1006, reason: state.closeReason))
            case .handshaking, .flushing:
                // Sized against the text bound while the mode is unknown: the daemon can still
                // select plain base64, and a frame that fits the stricter bound fits either.
                let wireBytes = Self.wireByteCount(
                    kind: kind, plaintextBytes: frame.count, binaryCiphertext: false)
                guard wireBytes <= configuration.maximumWireBytes else {
                    return .tooLarge(wireBytes)
                }
                if state.pending.count >= configuration.maximumPendingSends {
                    state.pending.removeFirst()
                }
                state.pending.append(Pending(kind: kind, data: frame))
                return .queued
            case .open:
                guard var sender = state.sender else {
                    return .fail(WebSocketClosed(code: 1006, reason: "relay channel has no key"))
                }
                let wireBytes = Self.wireByteCount(
                    kind: kind, plaintextBytes: frame.count,
                    binaryCiphertext: state.binaryCiphertext)
                guard wireBytes <= configuration.maximumWireBytes else {
                    return .tooLarge(wireBytes)
                }
                guard let record = Self.protect(kind, frame, sender: &sender) else {
                    return .fail(
                        WebSocketClosed(
                            code: RelayCloseCode.recordFailed, reason: "could not protect frame"))
                }
                state.sender = sender
                return .write(record, asBinary: kind == .binary && state.binaryCiphertext)
            }
        }

        switch decision {
        case .queued:
            return
        case .fail(let closed):
            throw closed
        case .tooLarge(let wireBytes):
            // Refuse this frame only: upstream rejects an oversized send without closing a
            // working socket.
            throw RelayTransportError.frameTooLarge(
                wireBytes: wireBytes, limit: configuration.maximumWireBytes)
        case .write(let record, let asBinary):
            try await write(record, asBinary: asBinary)
        }
    }

    private func write(_ record: [UInt8], asBinary: Bool) async throws {
        do {
            if asBinary {
                try await base.send(binary: Data(record))
            } else {
                try await base.send(text: Data(record).base64EncodedString())
            }
        } catch {
            let closed = Self.closedFrom(error)
            finish(code: closed.code, reason: closed.reason)
            throw closed
        }
    }

    // MARK: Receiving

    public func receive() async throws -> WebSocketFrame {
        for try await frame in stream {
            return frame
        }
        // Unreachable: the stream only finishes by throwing. Keeps the signature honest without
        // a force unwrap.
        throw WebSocketClosed(code: 1006, reason: "relay channel ended")
    }

    public func close(code: Int) {
        let shouldClose = mutex.withLock { state -> Bool in
            guard state.phase != .closed else { return false }
            state.phase = .closed
            state.closeCode = code
            state.closeReason = "client closed"
            state.pending = []
            state.sender = nil
            state.receiver = nil
            return true
        }
        guard shouldClose else { return }
        finish(code: code, reason: "client closed", closeBase: true)
    }

    /// Frames queued while the handshake runs. Internal: tests assert the cap without exposing the
    /// queue itself.
    var pendingFrameCount: Int { mutex.withLock { $0.pending.count } }

    public var negotiatedRelaySecurity: ConnectionOffer.Security? {
        mutex.withLock { state in
            switch state.phase {
            case .open, .flushing: return .protected
            case .handshaking, .closed: return nil
            }
        }
    }

    // MARK: Lifecycle

    private func start() {
        let hello = mutex.withLock { $0.helloText }
        let first = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.base.send(text: hello)
            } catch {
                // The relay or the daemon dropped us before answering: retryable, but the caller
                // must hear a code rather than a bare transport error.
                self.finish(
                    code: RelayCloseCode.neverOpened,
                    reason: Self.closedFrom(error).reason)
            }
        }
        let receive = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
        let clock = Task { [weak self] in
            guard let self else { return }
            await self.handshakeClock(hello: hello)
        }
        mutex.withLock { $0.clock = clock }
        taskLock.withLock { $0 = [first, receive, clock] }
    }

    private func cancelTasks() {
        let tasks = taskLock.withLock { current -> [Task<Void, Never>] in
            let copy = current
            current.removeAll()
            return copy
        }
        tasks.forEach { $0.cancel() }
    }

    /// Retries the byte-identical hello once a second, then gives up with 4002. A regenerated
    /// ephemeral or a re-encoded envelope would make the daemon close 1008 on the transcript.
    private func handshakeClock(hello: String) async {
        let deadline = ContinuousClock.now + configuration.handshakeTimeout
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: configuration.handshakeRetryInterval)
            } catch {
                return
            }
            enum Action { case stop, retry, timedOut }
            let action = mutex.withLock { state -> Action in
                switch state.phase {
                case .closed, .flushing, .open: return .stop
                case .handshaking: return ContinuousClock.now >= deadline ? .timedOut : .retry
                }
            }
            switch action {
            case .stop:
                return
            case .retry:
                do {
                    try await base.send(text: hello)
                } catch {
                    finish(
                        code: RelayCloseCode.neverOpened, reason: Self.closedFrom(error).reason)
                    return
                }
            case .timedOut:
                finish(
                    code: RelayCloseCode.protectedHandshakeFailed,
                    reason: "protected handshake timed out")
                return
            }
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            let frame: WebSocketFrame
            do {
                frame = try await base.receive()
            } catch {
                let closed = Self.closedFrom(error)
                let neverOpened = mutex.withLock { $0.phase == .handshaking }
                // A relay replaces a daemon-side close with its own code, so "closed during the
                // handshake" is all we can honestly report: 4001, retryable.
                finish(
                    code: neverOpened ? RelayCloseCode.neverOpened : closed.code,
                    reason: closed.reason)
                return
            }
            handle(frame)
            if mutex.withLock({ $0.phase == .closed }) { return }
        }
    }

    private func handle(_ frame: WebSocketFrame) {
        switch frame {
        case .binary(let data):
            decrypt(Array(data))
        case .text(let text):
            let handshaking = mutex.withLock { $0.phase == .handshaking }
            if handshaking {
                switch Self.classify(text) {
                case .ready(let ready):
                    completeHandshake(ready)
                case .malformedReady:
                    finish(
                        code: RelayCloseCode.protectedHandshakeFailed,
                        reason: "malformed ready envelope")
                case .other:
                    // Pre-open noise (a stale retry answer): ignore rather than treat as a record.
                    break
                }
                return
            }
            // After open, base64 records never start with `{`. A JSON frame here is plaintext
            // traffic on an encrypted channel, or a duplicate handshake envelope to ignore.
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                switch Self.classify(text) {
                case .ready, .malformedReady:
                    return  // a duplicate ready after open is ignored
                case .other:
                    finish(
                        code: RelayCloseCode.recordFailed,
                        reason: "plaintext frame on encrypted channel")
                    return
                }
            }
            guard let record = Data(base64Encoded: text) else {
                finish(code: RelayCloseCode.recordFailed, reason: "inbound record is not base64")
                return
            }
            decrypt(Array(record))
        }
    }

    private func decrypt(_ record: [UInt8]) {
        enum Outcome {
            case frame(RelayDecodedFrame)
            case notOpen
            case reject
        }
        let outcome = mutex.withLock { state -> Outcome in
            guard state.phase == .open || state.phase == .flushing,
                var receiver = state.receiver
            else { return .notOpen }
            do {
                let frame = try RelayRecordCodec.decode(record, receiver: &receiver)
                state.receiver = receiver
                return .frame(frame)
            } catch {
                return .reject
            }
        }
        switch outcome {
        case .frame(let frame):
            switch frame.kind {
            case .text:
                guard let text = String(bytes: frame.data, encoding: .utf8) else {
                    finish(
                        code: RelayCloseCode.recordFailed,
                        reason: "inbound text record is not UTF-8")
                    return
                }
                continuation.yield(.text(text))
            case .binary:
                continuation.yield(.binary(Data(frame.data)))
            }
        case .notOpen:
            return
        case .reject:
            // Authentication or framing failure: close 4003 and deliver nothing further, rather
            // than surfacing a partial frame.
            finish(
                code: RelayCloseCode.recordFailed,
                reason: "inbound record failed authentication or framing")
        }
    }

    // MARK: Handshake

    private func completeHandshake(_ ready: RelayReadyEnvelope) {
        guard let envelope = ready.protected else {
            // A legacy ready means the daemon predates 0.13 or the relay is doing something
            // clever. Legacy has no replay protection and needs XSalsa20, so it is refused here
            // unconditionally.
            finish(
                code: RelayCloseCode.protectedHandshakeFailed,
                reason: "daemon offered only legacy endpoint security")
            return
        }
        guard envelope.v == Self.protectedEnvelopeVersion else {
            finish(
                code: RelayCloseCode.protectedHandshakeFailed,
                reason: "unsupported protected envelope version")
            return
        }
        guard let message2 = Data(base64Encoded: envelope.message) else {
            finish(
                code: RelayCloseCode.protectedHandshakeFailed,
                reason: "ready message is not base64")
            return
        }

        enum Outcome {
            case open(NoiseCipherState, NoiseCipherState, Bool)
            case refuse(String)
        }
        let outcome = mutex.withLock { state -> Outcome in
            guard state.phase == .handshaking else { return .refuse("handshake already settled") }
            do {
                let payload = try state.handshake.readMessage(Array(message2))
                let selected = try RelayHandshakeParameters(decoding: payload)
                // We offered binary ciphertext. Selecting it off again is an unoffered parameter,
                // and would mean the framing we decode is not the framing the daemon uses.
                guard selected.binaryCiphertext else {
                    return .refuse("daemon selected an unoffered parameter")
                }
                let keys = try state.handshake.split()
                return .open(keys.send, keys.receive, selected.binaryCiphertext)
            } catch {
                return .refuse("protected handshake failed")
            }
        }

        switch outcome {
        case .refuse(let reason):
            finish(code: RelayCloseCode.protectedHandshakeFailed, reason: reason)
        case .open(let sender, let receiver, let binaryCiphertext):
            let pending = mutex.withLock { state -> [Pending] in
                state.phase = .flushing
                state.sender = sender
                state.receiver = receiver
                state.binaryCiphertext = binaryCiphertext
                let pending = state.pending
                state.pending = []
                return pending
            }
            mutex.withLock { $0.clock?.cancel() }
            Task { [weak self] in
                guard let self else { return }
                await self.drain(pending)
            }
        }
    }

    /// Writes frames queued during the handshake, in order, before anything newer. New sends keep
    /// appending until the queue is empty, so order survives a burst.
    private func drain(_ initial: [Pending]) async {
        var batch = initial
        while true {
            for item in batch {
                guard !Task.isCancelled else { return }
                let decision = mutex.withLock { state -> Decision in
                    guard state.phase == .flushing, var sender = state.sender else {
                        return .fail(
                            WebSocketClosed(
                                code: state.closeCode ?? 1006, reason: state.closeReason))
                    }
                    // `submit` sized this frame against the text bound, so it fits either mode
                    // the daemon could have selected. Size is not re-checked here.
                    guard let record = Self.protect(item.kind, item.data, sender: &sender) else {
                        return .fail(
                            WebSocketClosed(
                                code: RelayCloseCode.recordFailed,
                                reason: "could not protect queued frame"))
                    }
                    state.sender = sender
                    return .write(
                        record, asBinary: item.kind == .binary && state.binaryCiphertext)
                }
                switch decision {
                case .write(let record, let asBinary):
                    do {
                        try await write(record, asBinary: asBinary)
                    } catch {
                        return
                    }
                case .queued, .tooLarge:
                    continue
                case .fail(let closed):
                    finish(code: closed.code, reason: closed.reason)
                    return
                }
            }

            batch = mutex.withLock { state -> [Pending] in
                guard state.phase == .flushing else { return [] }
                if state.pending.isEmpty {
                    state.phase = .open
                    return []
                }
                let pending = state.pending
                state.pending = []
                return pending
            }
            if batch.isEmpty { return }
        }
    }

    // MARK: Termination

    /// Delivers the close to `receive()` exactly once, then closes the base socket.
    private func finish(code: Int, reason: String, closeBase: Bool = true) {
        let shouldFinish = mutex.withLock { state -> Bool in
            guard !state.finished else { return false }
            state.finished = true
            state.phase = .closed
            state.closeCode = code
            state.closeReason = reason
            state.pending = []
            state.sender = nil
            state.receiver = nil
            return true
        }
        guard shouldFinish else { return }
        cancelTasks()
        continuation.finish(throwing: WebSocketClosed(code: code, reason: reason))
        if closeBase { base.close(code: code) }
    }

    // MARK: Wire helpers

    private static let protectedEnvelopeVersion = 1

    private static func protect(
        _ kind: RelayFrameKind, _ frame: [UInt8], sender: inout NoiseCipherState
    ) -> [UInt8]? {
        do {
            return try RelayRecordCodec.encode(kind: kind, frame: frame, sender: &sender)
        } catch {
            return nil
        }
    }

    private static func helloText(message1: [UInt8], legacyPublicKey: [UInt8]) -> String {
        let envelope: [String: Any] = [
            "type": "e2ee_hello",
            "key": Data(legacyPublicKey).base64EncodedString(),
            "capabilities": ["binaryCiphertext": true],
            "protected": [
                "v": protectedEnvelopeVersion,
                "message": Data(message1).base64EncodedString(),
            ],
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: envelope, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return #"{"type":"e2ee_hello"}"# }
        return text
    }

    struct RelayReadyEnvelope: Equatable {
        var protected: ProtectedEnvelope?

        struct ProtectedEnvelope: Equatable {
            var v: Int
            var message: String
        }
    }

    enum HandshakeFrame: Equatable {
        case ready(RelayReadyEnvelope)
        case malformedReady
        case other
    }

    static func classify(_ text: String) -> HandshakeFrame {
        guard let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = root["type"] as? String,
            type == "e2ee_ready" || type == "e2ee_hello"
        else { return .other }
        guard type == "e2ee_ready" else { return .other }
        var envelope = RelayReadyEnvelope()
        if let protected = root["protected"] as? [String: Any] {
            guard let version = protected["v"] as? Int, let message = protected["message"] as? String
            else { return .malformedReady }
            envelope.protected = .init(v: version, message: message)
        }
        return .ready(envelope)
    }

    private static func closedFrom(_ error: any Error) -> WebSocketClosed {
        if let closed = error as? WebSocketClosed { return closed }
        return WebSocketClosed(code: 1006, reason: String(describing: error))
    }

    /// Bytes this frame occupies on the relay socket: the record itself for binary, or its base64
    /// expansion for text — which is what the relay's 32 MiB per-message limit counts.
    static func wireByteCount(
        kind: RelayFrameKind, plaintextBytes: Int, binaryCiphertext: Bool
    ) -> Int {
        let record = RelayRecordCodec.protectedRecordByteLength(plaintextBytes)
        if kind == .binary, binaryCiphertext { return record }
        return 4 * ((record + 2) / 3)
    }
}

extension RelayWebSocketTransport.HandshakeFrame {
    /// `true` for a ready this client can act on, so tests read the classifier directly.
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}
