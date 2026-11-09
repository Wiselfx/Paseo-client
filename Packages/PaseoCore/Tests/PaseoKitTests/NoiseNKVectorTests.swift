import Foundation
import PaseoFixtures
import Testing
@testable import PaseoKit

/// R16: `Noise_NK_25519_ChaChaPoly_SHA256` against the vendored third-party vectors from
/// rweather/noise-c ("cacophony"), the same file the daemon's relay package tests against.
///
/// Only the initiator is implemented, which is enough to check every byte: message 1 is ours,
/// message 2 is read, then the transport messages alternate initiator/responder.
@Suite struct NoiseNKVectorTests {
    // MARK: Fixture

    struct Vector: Decodable {
        struct Message: Decodable {
            let payload: String
            let ciphertext: String
        }

        let name: String
        let pattern: String
        let dh: String
        let cipher: String
        let hash: String
        let initPrologue: String
        let initEphemeral: String
        let initRemoteStatic: String
        let respPrologue: String
        let respStatic: String
        let respEphemeral: String
        let messages: [Message]
        let handshakeHash: String?

        enum CodingKeys: String, CodingKey {
            case name, pattern, dh, cipher, hash, messages
            case initPrologue = "init_prologue"
            case initEphemeral = "init_ephemeral"
            case initRemoteStatic = "init_remote_static"
            case respPrologue = "resp_prologue"
            case respStatic = "resp_static"
            case respEphemeral = "resp_ephemeral"
            case handshakeHash = "handshake_hash"
        }
    }

    struct VectorFile: Decodable {
        let vectors: [Vector]
    }

    static func vectors() throws -> [Vector] {
        let data = try Fixture.relay("nk-25519-chachapoly-sha256")
        return try JSONDecoder().decode(VectorFile.self, from: data).vectors
    }

    // MARK: Vectors

    @Test func everyVectorHandshakeAndTransportMessageMatches() throws {
        let vectors = try Self.vectors()
        #expect(vectors.count == 2)
        // Exactly one vector carries the handshake hash; the other predates the field.
        #expect(vectors.filter { $0.handshakeHash != nil }.count == 1)
        var checkedHashes = 0

        for vector in vectors {
            #expect(vector.name == NoiseNK.protocolName)
            #expect(vector.pattern == "NK")
            #expect(vector.dh == "25519")
            #expect(vector.cipher == "ChaChaPoly")
            #expect(vector.hash == "SHA256")

            // Our X25519 agrees with the vector: deriving the responder's public key from its
            // static secret reproduces the key the initiator is told out of band.
            let responderStatic = try NoiseKeyPair(
                secretKey: Hex.bytes(vector.respStatic))
            #expect(Hex.string(responderStatic.publicKey) == vector.initRemoteStatic)

            var initiator = try NoiseNK(
                remoteStatic: Hex.bytes(vector.initRemoteStatic),
                prologue: Hex.bytes(vector.initPrologue),
                ephemeral: try NoiseKeyPair(secretKey: Hex.bytes(vector.initEphemeral)))

            let handshake = vector.messages.prefix(2)
            let transport = vector.messages.dropFirst(2)
            let first = try #require(handshake.first)
            let second = try #require(handshake.dropFirst().first)

            let msg1 = try initiator.writeMessage(payload: Hex.bytes(first.payload))
            #expect(Hex.string(msg1) == first.ciphertext)
            let msg2 = try initiator.readMessage(Hex.bytes(second.ciphertext))
            #expect(Hex.string(msg2) == second.payload)
            #expect(initiator.isComplete)
            if let expectedHash = vector.handshakeHash {
                #expect(Hex.string(initiator.handshakeHash()) == expectedHash)
                checkedHashes += 1
            }

            var keys = try initiator.split()
            for (offset, message) in transport.enumerated() {
                let payload = try Hex.bytes(message.payload)
                let ciphertext = try Hex.bytes(message.ciphertext)
                if offset % 2 == 0 {
                    // Initiator → responder.
                    let sealed = try keys.send.encrypt(plaintext: payload)
                    #expect(Hex.string(sealed) == message.ciphertext)
                } else {
                    // Responder → initiator.
                    let opened = try keys.receive.decrypt(ciphertext: ciphertext)
                    #expect(Hex.string(opened) == message.payload)
                }
            }
        }
        #expect(checkedHashes == 1)
    }

    @Test func productionPrologueIsTheRelayLabel() {
        #expect(String(decoding: NoiseNK.prologue, as: UTF8.self) == "paseo-relay-e2ee/1")
        #expect(NoiseNK.protocolName == "Noise_NK_25519_ChaChaPoly_SHA256")
    }

    // MARK: Handshake state machine

    @Test func handshakeRefusesMessagesOutOfTurnAndTwice() throws {
        let vector = try #require(try Self.vectors().first)
        var initiator = try Self.initiator(vector)

        #expect(throws: NoiseError.handshakeOutOfTurn) {
            try initiator.readMessage(try Hex.bytes(vector.messages[1].ciphertext))
        }
        #expect(throws: NoiseError.handshakeIncomplete) { try initiator.split() }

        _ = try initiator.writeMessage(payload: Hex.bytes(vector.messages[0].payload))
        #expect(throws: NoiseError.handshakeOutOfTurn) {
            _ = try initiator.writeMessage(payload: [])
        }
        _ = try initiator.readMessage(try Hex.bytes(vector.messages[1].ciphertext))
        #expect(throws: NoiseError.handshakeComplete) {
            _ = try initiator.writeMessage(payload: [])
        }
        _ = try initiator.split()
        #expect(throws: NoiseError.handshakeComplete) { try initiator.split() }
    }

    @Test func aTamperedSecondMessageFailsAuthentication() throws {
        let vector = try #require(try Self.vectors().first)
        let payload1 = try Hex.bytes(vector.messages[0].payload)
        let msg2 = try Hex.bytes(vector.messages[1].ciphertext)

        var tampered = try Self.initiator(vector)
        _ = try tampered.writeMessage(payload: payload1)
        var corrupted = msg2
        corrupted[corrupted.count - 1] ^= 0x01
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try tampered.readMessage(corrupted)
        }
        // A failed read poisons the handshake: the transcript can no longer be trusted, which is
        // why the caller must close the socket (4002) rather than retry on the same channel.
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try tampered.readMessage(msg2)
        }

        var clean = try Self.initiator(vector)
        _ = try clean.writeMessage(payload: payload1)
        let payload2 = try Hex.bytes(vector.messages[1].payload)
        let read2 = try clean.readMessage(msg2)
        #expect(read2 == payload2)
    }

    @Test func handshakeMessagesOverTheNoiseLimitAreRefused() throws {
        let vector = try #require(try Self.vectors().first)
        var initiator = try Self.initiator(vector)
        #expect(throws: NoiseError.messageTooLarge) {
            _ = try initiator.readMessage([UInt8](repeating: 0, count: NoiseNK.maxMessageBytes + 1))
        }
    }

    // MARK: Keys

    @Test func keysOfTheWrongLengthAreRefused() throws {
        let vector = try #require(try Self.vectors().first)
        let remote = try Hex.bytes(vector.initRemoteStatic)
        #expect(throws: NoiseError.invalidKeyLength("remote static key must be 32 bytes")) {
            _ = try NoiseNK(remoteStatic: Array(remote.dropLast()), prologue: [])
        }
        #expect(throws: NoiseError.invalidKeyLength("public key must be 32 bytes")) {
            _ = try NoiseKeyPair(
                publicKey: Array(remote.dropLast()), secretKey: [UInt8](repeating: 1, count: 32))
        }
        #expect(throws: NoiseError.invalidKeyLength("secret key must be 32 bytes")) {
            _ = try NoiseKeyPair(secretKey: Array(remote.dropLast()))
        }
    }

    /// X25519 low-order/unsupported peers. The daemon's relay package rejects exactly this list.
    static let lowOrderPeerKeys: [String] = [
        String(repeating: "00", count: 32),
        "01" + String(repeating: "00", count: 31),
        "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800",
        "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
        "ec" + String(repeating: "ff", count: 30) + "7f",
        "ed" + String(repeating: "ff", count: 30) + "7f",
        "ee" + String(repeating: "ff", count: 30) + "7f",
    ]

    @Test(arguments: lowOrderPeerKeys)
    func lowOrderPeerKeysAreRefused(_ hex: String) throws {
        let secretKey = NoiseKeyPair.random().secretKey
        let peer = try Hex.bytes(hex)
        #expect(throws: NoiseError.invalidPublicKey) {
            _ = try NoiseNK.dh(secretKey: secretKey, publicKey: peer)
        }
    }

    // MARK: Parameters

    @Test func parameterPayloadRoundTripsAndRejectsUnknownBits() throws {
        #expect(try RelayHandshakeParameters(decoding: [0x01, 0x01]).binaryCiphertext)
        #expect(try RelayHandshakeParameters(decoding: [0x01, 0x00]).binaryCiphertext == false)
        #expect(RelayHandshakeParameters(binaryCiphertext: true).encoded() == [0x01, 0x01])
        #expect(RelayHandshakeParameters(binaryCiphertext: false).encoded() == [0x01, 0x00])

        #expect(throws: NoiseError.invalidParameterPayload) {
            _ = try RelayHandshakeParameters(decoding: [0x01])
        }
        #expect(throws: NoiseError.invalidParameterPayload) {
            _ = try RelayHandshakeParameters(decoding: [0x01, 0x00, 0x00])
        }
        #expect(throws: NoiseError.unsupportedParameterVersion) {
            _ = try RelayHandshakeParameters(decoding: [0x02, 0x00])
        }
        #expect(throws: NoiseError.reservedParameterFlag) {
            _ = try RelayHandshakeParameters(decoding: [0x01, 0x80])
        }
    }

    // MARK: Helpers

    private static func initiator(_ vector: Vector) throws -> NoiseNK {
        try NoiseNK(
            remoteStatic: Hex.bytes(vector.initRemoteStatic),
            prologue: Hex.bytes(vector.initPrologue),
            ephemeral: try NoiseKeyPair(secretKey: Hex.bytes(vector.initEphemeral)))
    }
}

// MARK: - Hex

enum Hex {
    static func bytes(_ hex: String) throws -> [UInt8] {
        guard hex.count % 2 == 0 else { throw HexError.odd }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw HexError.invalid }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    enum HexError: Error { case odd, invalid }
}
