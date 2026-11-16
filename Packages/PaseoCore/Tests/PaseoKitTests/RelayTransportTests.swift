import Foundation
import PaseoKit
import Testing
@testable import PaseoKit

/// R17: the protected relay socket. Every case drives real Noise bytes through `FakeRelaySocket`,
/// whose daemon half lives in `RelayResponderFake.swift`.
@Suite struct RelayTransportTests {
    static let link = DaemonEndpoint.RelayLink(
        serverID: "srv_AAAAAAAAAAAA", daemonPublicKeyB64: "", daemonPublicKey: [UInt8]())

    /// A link whose key matches the fake daemon.
    static func link(for peer: RelayDaemonPeer) -> DaemonEndpoint.RelayLink {
        DaemonEndpoint.RelayLink(
            serverID: "srv_AAAAAAAAAAAA", daemonPublicKeyB64: peer.publicKeyB64,
            daemonPublicKey: peer.staticKey.publicKey)
    }

    static func configuration(
        retry: Duration = .milliseconds(10),
        timeout: Duration = .milliseconds(300),
        pending: Int = 200,
        wire: Int = 32 * 1024 * 1024
    ) -> RelayWebSocketTransport.Configuration {
        var configuration = RelayWebSocketTransport.Configuration()
        configuration.handshakeRetryInterval = retry
        configuration.handshakeTimeout = timeout
        configuration.maximumPendingSends = pending
        configuration.maximumWireBytes = wire
        return configuration
    }

    static func makeTransport(
        peer: RelayDaemonPeer = RelayDaemonPeer(),
        configuration: RelayWebSocketTransport.Configuration = configuration()
    ) throws -> (transport: RelayWebSocketTransport, socket: FakeRelaySocket) {
        let socket = FakeRelaySocket(peer: peer)
        let transport = try RelayWebSocketTransport(
            base: socket, link: link(for: peer), configuration: configuration)
        return (transport, socket)
    }

    /// Waits until the protected channel is open.
    static func waitOpen(_ transport: RelayWebSocketTransport) async throws {
        try await waitUntil { transport.negotiatedRelaySecurity == .protected }
    }

    // MARK: Happy path

    @Test func theChannelOpensAndCarriesBothDirections() async throws {
        let (transport, socket) = try Self.makeTransport()
        defer { transport.close(code: 1000) }

        try await transport.send(text: #"{"type":"hello"}"#)
        try await Self.waitOpen(transport)
        #expect(transport.negotiatedRelaySecurity == .protected)
        #expect(socket.peer.isOpen)
        try await waitUntil { socket.peer.receivedTexts == [#"{"type":"hello"}"#] }

        socket.pushDaemonText(#"{"type":"session"}"#)
        let frame = try await transport.receive()
        #expect(frame == .text(#"{"type":"session"}"#))
    }

    @Test func binaryRecordsRideAsBinaryAndTextRecordsAsBase64() async throws {
        let (transport, socket) = try Self.makeTransport()
        defer { transport.close(code: 1000) }
        try await Self.waitOpen(transport)

        let payload = Data([0x00, 0x01, 0xFE, 0xFF])
        try await transport.send(binary: payload)
        try await transport.send(text: "hello")
        try await waitUntil { socket.peer.receivedBinaries == [payload] }
        #expect(socket.peer.receivedTexts == ["hello"])

        // Binary ciphertext was negotiated, so a binary frame goes out as a WS binary frame; text
        // frames are always base64 and never look like JSON.
        #expect(socket.binarySendCount >= 1)
        let textFrames = socket.sent.compactMap { frame -> String? in
            if case .text(let text) = frame { return text }
            return nil
        }
        let recordFrames = textFrames.filter { !$0.contains("e2ee_") }
        #expect(recordFrames.count == 1)
        #expect(Data(base64Encoded: recordFrames[0]) != nil)
    }

    @Test func framesSentDuringTheHandshakeAreQueuedInOrder() async throws {
        // A silent daemon keeps the channel closed while the client keeps sending.
        let peer = RelayDaemonPeer(behaviour: .silent)
        let (transport, socket) = try Self.makeTransport(
            peer: peer, configuration: Self.configuration(retry: .seconds(30), timeout: .seconds(30)))
        defer { transport.close(code: 1000) }

        try await waitUntil { socket.textSendCount == 1 }
        for index in 0..<5 {
            try await transport.send(text: "frame-\(index)")
        }
        #expect(socket.peer.receivedTexts.isEmpty)
        // Nothing was written to the socket except the hello.
        #expect(socket.textSendCount == 1)
    }

    @Test func thePendingQueueDropsTheOldestFrames() async throws {
        let peer = RelayDaemonPeer(behaviour: .delayed)
        let (transport, socket) = try Self.makeTransport(
            peer: peer,
            configuration: Self.configuration(
                retry: .seconds(30), timeout: .seconds(30), pending: 3))
        defer { transport.close(code: 1000) }

        try await waitUntil { socket.textSendCount == 1 }
        for index in 0..<5 {
            try await transport.send(text: "frame-\(index)")
        }
        #expect(transport.pendingFrameCount == 3)
        #expect(socket.peer.receivedTexts.isEmpty)

        // The cap is upstream's: keep the newest, drop the oldest, flush in order.
        socket.deliverHeldReady()
        try await Self.waitOpen(transport)
        try await waitUntil { socket.peer.receivedTexts.count == 3 }
        #expect(socket.peer.receivedTexts == ["frame-2", "frame-3", "frame-4"])
    }

    // MARK: Handshake retries

    @Test func theHelloIsResentByteForByteUntilReady() async throws {
        let peer = RelayDaemonPeer(behaviour: .silent)
        let socket = FakeRelaySocket(peer: peer)
        let transport = try RelayWebSocketTransport(
            base: socket, link: Self.link(for: peer),
            configuration: Self.configuration(retry: .milliseconds(5), timeout: .seconds(30)))
        defer { transport.close(code: 1000) }

        try await waitUntil(timeout: .seconds(2)) { socket.textSendCount >= 3 }
        let hellos = socket.sent.compactMap { frame -> String? in
            if case .text(let text) = frame { return text }
            return nil
        }
        #expect(hellos.count >= 3)
        #expect(Set(hellos).count == 1)
        // The same msg1 inside the same envelope: a regenerated ephemeral would look like a
        // re-handshake and close the daemon's channel with 1008.
        #expect(hellos[0].contains("\"e2ee_hello\""))
        #expect(hellos[0].contains("\"protected\""))
        #expect(hellos[0].contains("\"binaryCiphertext\":true"))
    }

    @Test func aSilentDaemonFailsTheHandshakeWith4002() async throws {
        let peer = RelayDaemonPeer(behaviour: .silent)
        let (transport, socket) = try Self.makeTransport(
            peer: peer, configuration: Self.configuration(retry: .milliseconds(5), timeout: .milliseconds(60)))
        #expect(transport.negotiatedRelaySecurity == nil)

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4002)
        #expect(closed?.reason == "protected handshake timed out")
        try await Self.waitForClientClose(socket)
        #expect(socket.clientCloseCode == 4002)
    }

    @Test func aSocketThatDiesDuringTheHandshakeReports4001() async throws {
        let (transport, socket) = try Self.makeTransport(
            peer: RelayDaemonPeer(behaviour: .silent),
            configuration: Self.configuration(retry: .seconds(30), timeout: .seconds(30)))
        socket.serverClose(code: 1012, reason: "relay restart")

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4001)
        #expect(closed?.reason == "relay restart")
    }

    // MARK: Refusing legacy and malformed handshakes

    @Test(arguments: [
        RelayPeerBehaviour.legacyOnly, .malformedReady, .unsupportedVersion,
    ])
    func aReadyWithoutAWorkingProtectedEnvelopeIs4002(_ behaviour: RelayPeerBehaviour) async throws {
        let peer = RelayDaemonPeer(behaviour: behaviour)
        let (transport, socket) = try Self.makeTransport(peer: peer)

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4002)
        try await Self.waitForClientClose(socket)
        #expect(socket.clientCloseCode == 4002)
        #expect(transport.negotiatedRelaySecurity == nil)
    }

    @Test func aLegacyReadyNamesItsRefusal() async throws {
        let peer = RelayDaemonPeer(behaviour: .legacyOnly)
        let (transport, _) = try Self.makeTransport(peer: peer)
        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.reason == "daemon offered only legacy endpoint security")
    }

    @Test func anUnsupportedEnvelopeVersionNamesItsRefusal() async throws {
        let peer = RelayDaemonPeer(behaviour: .unsupportedVersion)
        let (transport, _) = try Self.makeTransport(peer: peer)
        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.reason == "unsupported protected envelope version")
    }

    @Test func aReadyThatFailsAuthenticationIs4002() async throws {
        let peer = RelayDaemonPeer(behaviour: .silent)
        let socket = FakeRelaySocket(peer: peer)
        let transport = try RelayWebSocketTransport(
            base: socket, link: Self.link(for: peer),
            configuration: Self.configuration(retry: .milliseconds(5), timeout: .milliseconds(400)))
        defer { transport.close(code: 1000) }

        // A ready with a syntactically fine but unauthenticated message.
        let bogus = Data([UInt8](repeating: 0x41, count: 48)).base64EncodedString()
        socket.push(.text(#"{"type":"e2ee_ready","protected":{"v":1,"message":"\#(bogus)"}}"#))
        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4002)
        #expect(closed?.reason == "protected handshake failed")
    }

    // MARK: Records

    @Test func aTamperedRecordCloses4003AndDeliversNothing() async throws {
        let (transport, socket) = try Self.makeTransport(peer: RelayDaemonPeer(behaviour: .tamperDaemonRecord))
        try await Self.waitOpen(transport)
        socket.pushDaemonText(#"{"type":"secret"}"#)

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4003)
        try await Self.waitForClientClose(socket)
        #expect(socket.clientCloseCode == 4003)
    }

    @Test func plaintextJSONAfterOpenCloses4003() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        // A relay that strips the encryption and injects a frame.
        socket.push(.text(#"{"type":"session","message":{"type":"status"}}"#))

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4003)
        #expect(closed?.reason == "plaintext frame on encrypted channel")
    }

    @Test func aDuplicateReadyAfterOpenIsIgnored() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        socket.push(.text(#"{"type":"e2ee_ready","protected":{"v":1,"message":"AAAA"}}"#))
        socket.pushDaemonText("after")

        #expect(try await transport.receive() == .text("after"))
    }

    @Test func aRecordThatIsNotBase64Closes4003() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        socket.push(.text("not-a-record"))

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 4003)
        #expect(closed?.reason == "inbound record is not base64")
    }

    @Test func binaryRecordsRoundTripInbound() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        let payload = Data((0..<64).map { UInt8($0) })
        socket.pushDaemonBinary(payload)

        #expect(try await transport.receive() == .binary(payload))
    }

    // MARK: Size limit

    @Test func anOversizedFrameIsRefusedWithoutClosingTheSocket() async throws {
        let (transport, socket) = try Self.makeTransport()
        defer { transport.close(code: 1000) }
        try await Self.waitOpen(transport)

        // The shared bound is conservative (it takes the tighter of the two modes), so go a
        // little past it to be unambiguously over the relay's 32 MiB.
        let limit = RelayRecordCodec.maxPlaintextByteLength(wireBytes: 32 * 1024 * 1024)
        let oversized = limit + 4_096
        let frame = String(repeating: "a", count: oversized)
        let thrown = await Self.error { try await transport.send(text: frame) }
        let expected = RelayTransportError.frameTooLarge(
            wireBytes: RelayWebSocketTransport.wireByteCount(
                kind: .text, plaintextBytes: oversized, binaryCiphertext: true),
            limit: 32 * 1024 * 1024)
        #expect(thrown as? RelayTransportError == expected)

        // The channel is still usable.
        #expect(socket.clientCloseCode == nil)
        try await transport.send(text: "still here")
        try await waitUntil { socket.peer.receivedTexts.contains("still here") }
    }

    @Test func theLargestFrameThatFitsIsAccepted() async throws {
        let (transport, socket) = try Self.makeTransport()
        defer { transport.close(code: 1000) }
        try await Self.waitOpen(transport)
        let limit = RelayRecordCodec.maxPlaintextByteLength(wireBytes: 32 * 1024 * 1024)
        let frame = String(repeating: "a", count: limit)
        #expect(RelayWebSocketTransport.wireByteCount(
            kind: .text, plaintextBytes: limit, binaryCiphertext: true) <= 32 * 1024 * 1024)
        try await transport.send(text: frame)
        try await waitUntil(timeout: .seconds(10)) {
            socket.peer.receivedTexts.first?.count == limit
        }
    }

    // MARK: Close

    @Test func closePropagatesTheCodeAndFailsLaterSends() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        transport.close(code: 1000)
        #expect(socket.clientCloseCode == 1000)

        let closed = await Self.closedError { try await transport.send(text: "late") }
        #expect(closed?.code == 1000)
        let receiveClosed = await Self.closedError { try await transport.receive() }
        #expect(receiveClosed?.code == 1000)
    }

    @Test func aDaemonCloseAfterOpenKeepsItsCode() async throws {
        let (transport, socket) = try Self.makeTransport()
        try await Self.waitOpen(transport)
        socket.serverClose(code: 1008, reason: "protected endpoint security required")

        let closed = await Self.closedError { try await transport.receive() }
        #expect(closed?.code == 1008)
        #expect(closed?.reason == "protected endpoint security required")
    }

    // MARK: Helpers

    /// Awaits the base socket's close code. `finish` wakes `receive()` and then closes the base
    /// socket from one task, but the woken reader runs on another: it can resume and read the code
    /// before `base.close` has run. So an awaited close error does not imply the socket is closed
    /// yet — the code has to be awaited, not read.
    static func waitForClientClose(_ socket: FakeRelaySocket) async throws {
        try await waitUntil { socket.clientCloseCode != nil }
    }

    static func closedError<T>(_ operation: () async throws -> T) async -> WebSocketClosed? {
        (await error(operation)) as? WebSocketClosed
    }

    static func error<T>(_ operation: () async throws -> T) async -> (any Error)? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }
}
