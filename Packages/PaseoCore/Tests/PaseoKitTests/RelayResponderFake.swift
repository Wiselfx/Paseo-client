import Crypto
import Foundation
import Synchronization
import Testing
@testable import PaseoKit

// The daemon half of the relay channel, in the test target only: the app is always the initiator.
// It exists so the transport tests exercise real Noise bytes in both directions (handshake,
// records, close codes) without a socket or this host's keypair.

/// `Noise_NK_25519_ChaChaPoly_SHA256`, responder side. Mirrors `packages/relay/src/noise/index.ts`
/// (`split` is mirrored for the responder: send is the second key).
struct NoiseResponder {
    private var symmetric: SymmetricState
    private let localStatic: NoiseKeyPair
    private var ephemeral: NoiseKeyPair?
    private var remoteEphemeral: [UInt8]?
    private var messageIndex = 0
    private var finished = false

    init(localStatic: NoiseKeyPair, prologue: [UInt8], ephemeral: NoiseKeyPair? = nil) {
        self.localStatic = localStatic
        self.ephemeral = ephemeral
        self.symmetric = SymmetricState(protocolName: NoiseNK.protocolName)
        symmetric.mixHash(prologue)
        symmetric.mixHash(localStatic.publicKey)
    }

    var isComplete: Bool { messageIndex >= 2 }

    /// Consumes message 1 (`-> e, es`) and returns its payload.
    mutating func readMessage(_ message: [UInt8]) throws -> [UInt8] {
        guard messageIndex == 0, !finished else { throw NoiseError.handshakeOutOfTurn }
        guard message.count >= 32 else { throw NoiseError.invalidPublicKey }
        let remote = Array(message.prefix(32))
        remoteEphemeral = remote
        symmetric.mixHash(remote)
        try symmetric.mixKey(NoiseNK.dh(secretKey: localStatic.secretKey, publicKey: remote))
        let payload = try symmetric.decryptAndHash(Array(message.dropFirst(32)))
        messageIndex += 1
        return payload
    }

    /// Builds message 2 (`<- e, ee`) with `payload` encrypted inside it.
    mutating func writeMessage(payload: [UInt8]) throws -> [UInt8] {
        guard messageIndex == 1, !finished else { throw NoiseError.handshakeOutOfTurn }
        guard let remoteEphemeral else { throw NoiseError.missingKey("remote ephemeral") }
        let keyPair = ephemeral ?? NoiseKeyPair.random()
        ephemeral = keyPair
        var message = keyPair.publicKey
        symmetric.mixHash(keyPair.publicKey)
        try symmetric.mixKey(NoiseNK.dh(secretKey: keyPair.secretKey, publicKey: remoteEphemeral))
        message += try symmetric.encryptAndHash(payload)
        messageIndex += 1
        return message
    }

    mutating func split() throws -> (send: NoiseCipherState, receive: NoiseCipherState) {
        guard isComplete, !finished else { throw NoiseError.handshakeIncomplete }
        finished = true
        let (initiatorSend, responderSend) = symmetric.split()
        return (send: NoiseCipherState(key: responderSend), receive: NoiseCipherState(key: initiatorSend))
    }
}

/// How the fake daemon answers the hello.
enum RelayPeerBehaviour {
    /// Normal: a protected ready, then records.
    case protected
    /// A pre-0.13 daemon: a ready with no protected envelope. The client must refuse with 4002.
    case legacyOnly
    /// A ready whose protected envelope is missing its message.
    case malformedReady
    /// A protected envelope with `v: 2`.
    case unsupportedVersion
    /// Never answers; the client's handshake clock must give up.
    case silent
    /// Builds the ready, holds it back until `takePendingReady()`, so a test can queue frames
    /// against a closed channel and then watch them flush.
    case delayed
    /// Answers normally, then fails to authenticate the first record the daemon sends.
    case tamperDaemonRecord
}

/// The daemon side of one relay session: the hello/ready transcript, the record keys, and the
/// bytes it received from the client.
final class RelayDaemonPeer: @unchecked Sendable {
    struct State {
        var noise: NoiseResponder?
        var sender: NoiseCipherState?
        var receiver: NoiseCipherState?
        var helloText: String?
        var readyText: String?
        var open = false
        var receivedTexts: [String] = []
        var receivedBinaries: [Data] = []
        var hellos = 0
        var daemonFrames = 0
        var heldReady: String?
    }

    let staticKey: NoiseKeyPair
    private let behaviour: RelayPeerBehaviour
    private let mutex = Mutex(State())

    /// - Parameter staticKey: pass the same key to two peers to simulate one daemon across a
    ///   reconnect; the default is a fresh key per peer, i.e. a different daemon.
    init(behaviour: RelayPeerBehaviour = .protected, staticKey: NoiseKeyPair = .random()) {
        self.staticKey = staticKey
        self.behaviour = behaviour
    }

    var publicKeyB64: String {
        Data(staticKey.publicKey).base64EncodedString()
    }

    var hellos: Int { mutex.withLock { $0.hellos } }
    var isOpen: Bool { mutex.withLock { $0.open } }
    var receivedTexts: [String] { mutex.withLock { $0.receivedTexts } }
    var receivedBinaries: [Data] { mutex.withLock { $0.receivedBinaries } }

    /// Handles a client text frame that is not a record yet: the hello, and nothing else.
    /// Returns frames to deliver back to the client.
    func handleClientText(_ text: String) -> [WebSocketFrame] {
        guard let data = text.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["type"] as? String == "e2ee_hello"
        else {
            // A record: decrypt it.
            return decryptRecordText(text)
        }
        return handleHello(text, root: root)
    }

    private func handleHello(_ text: String, root: [String: Any]) -> [WebSocketFrame] {
        enum Action {
            case answer(String)
            case cached(String)
            case mismatch
            case nothing
        }
        let action = mutex.withLock { state -> Action in
            state.hellos += 1
            if state.open {
                // An identical retry after open is fine; a different hello is a transcript
                // mismatch, which the real daemon closes with 1008.
                return state.helloText == text ? .nothing : .mismatch
            }
            if let helloText = state.helloText {
                if helloText == text, let ready = state.readyText { return .cached(ready) }
                if helloText != text { return .mismatch }
            }
            guard behaviour != .silent else { return .nothing }
            guard let protected = root["protected"] as? [String: Any],
                let message = protected["message"] as? String,
                let message1 = Data(base64Encoded: message)
            else {
                return .answer(#"{"type":"e2ee_ready"}"#)
            }
            switch behaviour {
            case .legacyOnly:
                return .answer(#"{"type":"e2ee_ready"}"#)
            case .malformedReady:
                return .answer(#"{"type":"e2ee_ready","protected":{"v":1}}"#)
            case .unsupportedVersion:
                return .answer(
                    #"{"type":"e2ee_ready","protected":{"v":2,"message":"AAAA"}}"#)
            case .protected, .tamperDaemonRecord, .delayed:
                break
            case .silent:
                return .nothing
            }
            var noise = NoiseResponder(
                localStatic: staticKey, prologue: NoiseNK.prologue)
            do {
                _ = try noise.readMessage(Array(message1))
                let message2 = try noise.writeMessage(
                    payload: RelayHandshakeParameters(binaryCiphertext: true).encoded())
                let keys = try noise.split()
                state.noise = noise
                state.sender = keys.send
                state.receiver = keys.receive
                state.open = true
                state.helloText = text
                let ready =
                    #"{"type":"e2ee_ready","protected":{"v":1,"message":"#
                    + "\"\(Data(message2).base64EncodedString())\"}}"
                state.readyText = ready
                if behaviour == .delayed {
                    state.heldReady = ready
                    return .nothing
                }
                return .answer(ready)
            } catch {
                return .mismatch
            }
        }

        switch action {
        case .answer(let ready), .cached(let ready):
            return [.text(ready)]
        case .mismatch:
            return []
        case .nothing:
            return []
        }
    }

    private func decryptRecordText(_ text: String) -> [WebSocketFrame] {
        guard let data = Data(base64Encoded: text) else { return [] }
        _ = consume(Array(data))
        return []
    }

    /// Feeds a client frame through the receive cipher. Returns the close code the daemon would
    /// send, if the record failed.
    @discardableResult
    func consume(_ record: [UInt8]) -> Int? {
        enum Outcome {
            case frame(RelayDecodedFrame)
            case refuse
            case notOpen
        }
        let outcome = mutex.withLock { state -> Outcome in
            guard state.open, var receiver = state.receiver else { return .notOpen }
            do {
                let frame = try RelayRecordCodec.decode(record, receiver: &receiver)
                state.receiver = receiver
                return .frame(frame)
            } catch {
                return .refuse
            }
        }
        switch outcome {
        case .notOpen:
            return nil
        case .refuse:
            return RelayCloseCode.daemonRecordFailure
        case .frame(let frame):
            mutex.withLock { state in
                if frame.kind == .text {
                    state.receivedTexts.append(String(decoding: frame.data, as: UTF8.self))
                } else {
                    state.receivedBinaries.append(Data(frame.data))
                }
            }
            return nil
        }
    }

    /// Hands over a ready held back by `.delayed`, once.
    func takePendingReady() -> String? {
        mutex.withLock { state in
            let ready = state.heldReady
            state.heldReady = nil
            return ready
        }
    }

    /// Encrypts a frame the daemon sends to the client.
    func encodeDaemonFrame(_ kind: RelayFrameKind, _ data: [UInt8]) -> WebSocketFrame? {
        let encoded = mutex.withLock { state -> WebSocketFrame? in
            guard state.open, var sender = state.sender else { return nil }
            do {
                var record = try RelayRecordCodec.encode(kind: kind, frame: data, sender: &sender)
                state.sender = sender
                // Corrupt only the first daemon frame: later ones stay honest so a test can prove
                // the channel closed rather than the payload was dropped.
                if behaviour == .tamperDaemonRecord, state.daemonFrames == 0 {
                    record[record.count - 1] ^= 0x01
                }
                state.daemonFrames += 1
                return kind == .binary
                    ? .binary(Data(record)) : .text(Data(record).base64EncodedString())
            } catch {
                return nil
            }
        }
        return encoded
    }
}

/// A `WebSocketTransport` pointed at the relay, with `RelayDaemonPeer` behind it. Everything the
/// client writes is decrypted by the peer; everything the peer sends is queued for `receive()`.
final class FakeRelaySocket: WebSocketTransport, @unchecked Sendable {
    private struct State {
        var inbound: [Result<WebSocketFrame, WebSocketClosed>] = []
        var waiter: CheckedContinuation<WebSocketFrame, any Error>?
        var clientCloseCode: Int?
        var sent: [WebSocketFrame] = []
        var binarySends = 0
        var textSends = 0
    }

    let peer: RelayDaemonPeer
    private let mutex = Mutex(State())

    init(peer: RelayDaemonPeer = RelayDaemonPeer()) {
        self.peer = peer
    }

    var clientCloseCode: Int? { mutex.withLock { $0.clientCloseCode } }
    var sent: [WebSocketFrame] { mutex.withLock { $0.sent } }
    var binarySendCount: Int { mutex.withLock { $0.binarySends } }
    var textSendCount: Int { mutex.withLock { $0.textSends } }

    func send(text: String) async throws {
        let closed = mutex.withLock { state -> Int? in
            guard state.clientCloseCode == nil else { return state.clientCloseCode }
            state.sent.append(.text(text))
            state.textSends += 1
            return nil
        }
        if let closed { throw WebSocketClosed(code: closed, reason: "client closed") }
        for frame in peer.handleClientText(text) {
            push(frame)
        }
    }

    func send(binary: Data) async throws {
        let closed = mutex.withLock { state -> Int? in
            guard state.clientCloseCode == nil else { return state.clientCloseCode }
            state.sent.append(.binary(binary))
            state.binarySends += 1
            return nil
        }
        if let closed { throw WebSocketClosed(code: closed, reason: "client closed") }
        if let code = peer.consume(Array(binary)) {
            serverClose(code: code, reason: "record failed")
        }
    }

    func receive() async throws -> WebSocketFrame {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = mutex.withLock { state -> Result<WebSocketFrame, WebSocketClosed>? in
                if !state.inbound.isEmpty { return state.inbound.removeFirst() }
                if let code = state.clientCloseCode {
                    return .failure(WebSocketClosed(code: code, reason: "client closed"))
                }
                state.waiter = continuation
                return nil
            }
            guard let immediate else { return }
            continuation.resume(with: immediate)
        }
    }

    func close(code: Int) {
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            state.clientCloseCode = code
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume(throwing: WebSocketClosed(code: code, reason: "client closed"))
    }

    // MARK: Test drivers

    /// Delivers a ready the peer was holding back.
    func deliverHeldReady() {
        guard let ready = peer.takePendingReady() else { return }
        push(.text(ready))
    }

    /// Queues a frame the daemon sends after the handshake.
    func pushDaemonText(_ text: String) {
        guard let frame = peer.encodeDaemonFrame(.text, Array(text.utf8)) else { return }
        push(frame)
    }

    func pushDaemonBinary(_ data: Data) {
        guard let frame = peer.encodeDaemonFrame(.binary, Array(data)) else { return }
        push(frame)
    }

    /// Queues a raw frame, bypassing the peer (for framing/plaintext attacks).
    func push(_ frame: WebSocketFrame) {
        push(.success(frame))
    }

    /// The relay or the daemon drops the socket.
    func serverClose(code: Int, reason: String = "closed by daemon") {
        let failure = WebSocketClosed(code: code, reason: reason)
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.inbound.append(.failure(failure))
            return nil
        }
        waiter?.resume(throwing: failure)
    }

    private func push(_ result: Result<WebSocketFrame, WebSocketClosed>) {
        let waiter = mutex.withLock { state -> CheckedContinuation<WebSocketFrame, any Error>? in
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            state.inbound.append(result)
            return nil
        }
        waiter?.resume(with: result)
    }
}

/// Builds `RelayWebSocketTransport`s over `FakeRelaySocket`s and keeps every socket it made.
final class FakeRelayFactory: @unchecked Sendable {
    private let mutex = Mutex<[FakeRelaySocket]>([])
    private let peers: [RelayDaemonPeer]

    init(peers: [RelayDaemonPeer] = [RelayDaemonPeer()]) {
        self.peers = peers
    }

    var sockets: [FakeRelaySocket] { mutex.withLock { $0 } }
    var count: Int { mutex.withLock { $0.count } }

    func makeFactory(configuration: RelayWebSocketTransport.Configuration = .init())
        -> WebSocketTransportFactory
    {
        let peers = self.peers
        return { [self] endpoint in
            let index = mutex.withLock { sockets -> Int in
                sockets.append(FakeRelaySocket(peer: peers[min(sockets.count, peers.count - 1)]))
                return sockets.count - 1
            }
            let socket = mutex.withLock { $0[index] }
            guard let relay = endpoint.relay else { return socket }
            do {
                return try RelayWebSocketTransport(
                    base: socket, link: relay, configuration: configuration)
            } catch {
                return ClosedTransport(
                    closed: WebSocketClosed(
                        code: RelayCloseCode.protectedHandshakeFailed,
                        reason: "invalid relay link"))
            }
        }
    }
}
