import Crypto
import Foundation

// The relay's endpoint security, daemon side key: Noise_NK_25519_ChaChaPoly_SHA256 (revision 34),
// initiator only. Spec: docs/research/11-relay-pairing.md §4.1.
//
//   NK:  <- s
//        ...
//        -> e, es
//        <- e, ee
//
// The daemon's static X25519 key arrives in the pairing offer, so `s` is trusted out of band and
// the phone is always the initiator. Records (`RelayRecordCodec`) ride on the split transport keys.

/// Everything this layer can refuse. Cases carry a short detail so a log line is diagnosable.
public enum NoiseError: Error, Equatable, Sendable {
    case invalidKeyLength(String)
    case invalidPublicKey
    case missingKey(String)
    case handshakeComplete
    case handshakeIncomplete
    case handshakeOutOfTurn
    case authenticationFailed
    case nonceExhausted
    case messageTooLarge
    case invalidParameterPayload
    case unsupportedParameterVersion
    case reservedParameterFlag
}

/// A raw X25519 keypair. Relayed daemon keys arrive base64 in the pairing offer; the ephemeral
/// half of the handshake is generated here and never leaves the device.
public struct NoiseKeyPair: Sendable, Equatable {
    public static let byteCount = 32

    public let publicKey: [UInt8]
    public let secretKey: [UInt8]

    public init(publicKey: [UInt8], secretKey: [UInt8]) throws {
        guard publicKey.count == Self.byteCount else {
            throw NoiseError.invalidKeyLength("public key must be 32 bytes")
        }
        guard secretKey.count == Self.byteCount else {
            throw NoiseError.invalidKeyLength("secret key must be 32 bytes")
        }
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    /// Derives the public half. Used for fixed test ephemerals; production only calls `random()`.
    public init(secretKey: [UInt8]) throws {
        guard secretKey.count == Self.byteCount else {
            throw NoiseError.invalidKeyLength("secret key must be 32 bytes")
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey)
        self.publicKey = Array(privateKey.publicKey.rawRepresentation)
        self.secretKey = secretKey
    }

    public static func random() -> NoiseKeyPair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        // A generated key always has 32-byte representations, so skip the validation path.
        return NoiseKeyPair(
            uncheckedPublicKey: Array(privateKey.publicKey.rawRepresentation),
            secretKey: Array(privateKey.rawRepresentation))
    }

    private init(uncheckedPublicKey: [UInt8], secretKey: [UInt8]) {
        self.publicKey = uncheckedPublicKey
        self.secretKey = secretKey
    }
}

/// The two-byte parameter payload both handshake messages carry: `[0x01 version][flags]`.
///
/// Only bit 0 is defined (`binaryCiphertext`). The daemon echoes the client's selection; anything
/// the client did not offer, an unknown version or a reserved bit is a failed handshake.
public struct RelayHandshakeParameters: Sendable, Equatable {
    public static let version: UInt8 = 0x01
    public static let binaryCiphertextFlag: UInt8 = 0x01
    private static let knownFlags: UInt8 = binaryCiphertextFlag

    /// Text frames are base64 ciphertext; binary frames may be raw bytes on the wire.
    public var binaryCiphertext: Bool

    public init(binaryCiphertext: Bool) {
        self.binaryCiphertext = binaryCiphertext
    }

    public func encoded() -> [UInt8] {
        [Self.version, binaryCiphertext ? Self.binaryCiphertextFlag : 0]
    }

    public init(decoding payload: [UInt8]) throws {
        guard payload.count == 2 else { throw NoiseError.invalidParameterPayload }
        guard payload[0] == Self.version else { throw NoiseError.unsupportedParameterVersion }
        guard payload[1] & ~Self.knownFlags == 0 else { throw NoiseError.reservedParameterFlag }
        self.binaryCiphertext = payload[1] & Self.binaryCiphertextFlag != 0
    }
}

/// One direction of the post-handshake cipher. A value type on purpose: whoever owns the channel
/// owns the counter, so a nonce is reserved before the frame leaves and never by two writers.
public struct NoiseCipherState: Sendable {
    public static let tagByteCount = 16
    public static let nonceByteCount = 12

    /// Raw key bytes rather than `SymmetricKey`: swift-crypto's `SymmetricKey` is not `Sendable`
    /// (CryptoKit's is), and this state must cross an actor boundary intact. The key is built once
    /// per operation, which costs a small allocation and nothing else.
    private var key: [UInt8]?
    private var nonce: UInt64 = 0

    /// 2^64 - 1 is the last usable nonce, as in the Noise spec.
    private static let maximumNonce = UInt64.max

    init(key: [UInt8]?) {
        self.key = key
    }

    public var hasKey: Bool { key != nil }
    public var nextNonce: UInt64 { nonce }

    /// `[0x00 0x00 0x00 0x00][n as 64-bit little endian]`.
    static func encodeNonce(_ value: UInt64) -> [UInt8] {
        var nonce = [UInt8](repeating: 0, count: nonceByteCount)
        for index in 4..<12 {
            nonce[index] = UInt8(truncatingIfNeeded: value >> (UInt64(index - 4) * 8))
        }
        return nonce
    }

    /// Encrypts and advances the counter. The nonce is reserved before any work is done, so two
    /// concurrent senders can never share one.
    public mutating func encrypt(plaintext: [UInt8], authenticating data: [UInt8] = []) throws -> [UInt8] {
        guard let keyBytes = key else { throw NoiseError.missingKey("send cipher has no key") }
        guard nonce != Self.maximumNonce else { throw NoiseError.nonceExhausted }
        let nonceValue = nonce
        nonce += 1
        let box = try ChaChaPoly.seal(
            plaintext, using: SymmetricKey(data: keyBytes),
            nonce: try ChaChaPoly.Nonce(data: Self.encodeNonce(nonceValue)), authenticating: data)
        return Array(box.ciphertext) + Array(box.tag)
    }

    /// Decrypts and advances the counter **only after the tag verifies**, so a rejected or
    /// duplicated record cannot desynchronise the stream.
    public mutating func decrypt(ciphertext: [UInt8], authenticating data: [UInt8] = []) throws -> [UInt8] {
        guard let keyBytes = key else {
            throw NoiseError.missingKey("receive cipher has no key")
        }
        guard nonce != Self.maximumNonce else { throw NoiseError.nonceExhausted }
        guard ciphertext.count >= Self.tagByteCount else { throw NoiseError.authenticationFailed }
        let body = ciphertext.prefix(ciphertext.count - Self.tagByteCount)
        let tag = ciphertext.suffix(Self.tagByteCount)
        let box = try ChaChaPoly.SealedBox(
            nonce: try ChaChaPoly.Nonce(data: Self.encodeNonce(nonce)),
            ciphertext: body, tag: tag)
        let plaintext: [UInt8]
        do {
            plaintext = Array(
                try ChaChaPoly.open(box, using: SymmetricKey(data: keyBytes), authenticating: data))
        } catch {
            throw NoiseError.authenticationFailed
        }
        nonce += 1
        return plaintext
    }

    /// Drops the key and parks the counter past the end, as the spec's `clear()` does.
    ///
    /// The bytes are released, not scrubbed: Swift arrays are copy-on-write and a stale copy could
    /// be elsewhere, so zeroing here would suggest a guarantee this cannot make. Key material for
    /// a relay channel is per-connection and short-lived; nothing is persisted.
    public mutating func clear() {
        key = nil
        nonce = Self.maximumNonce
    }
}

/// The initiator half of one relay handshake. A value type: `writeMessage`/`readMessage` mutate
/// the state machine, and the caller keeps the same instance across hello retries so the bytes
/// stay identical (a retried hello with different bytes closes the daemon's channel with 1008).
public struct NoiseNK: Sendable {
    public static let protocolName = "Noise_NK_25519_ChaChaPoly_SHA256"
    public static let prologue = Array("paseo-relay-e2ee/1".utf8)
    public static let maxMessageBytes = 65535
    static let dhByteCount = NoiseKeyPair.byteCount
    private static let messageCount = 2

    private var symmetric: SymmetricState
    private var ephemeral: NoiseKeyPair?
    private var remoteStatic: [UInt8]?
    private var remoteEphemeral: [UInt8]?
    private var messageIndex = 0
    private var finished = false

    /// - Parameters:
    ///   - remoteStatic: the daemon's static X25519 public key from the pairing offer.
    ///   - prologue: `NoiseNK.prologue` in production; tests inject the vector's prologue.
    ///   - ephemeral: test injection only. Production generates a fresh one per channel.
    public init(remoteStatic: [UInt8], prologue: [UInt8], ephemeral: NoiseKeyPair? = nil) throws {
        guard remoteStatic.count == Self.dhByteCount else {
            throw NoiseError.invalidKeyLength("remote static key must be 32 bytes")
        }
        self.symmetric = SymmetricState(protocolName: Self.protocolName)
        self.remoteStatic = remoteStatic
        self.ephemeral = ephemeral
        symmetric.mixHash(prologue)
        // Pre-message "<- s".
        symmetric.mixHash(remoteStatic)
    }

    public var isComplete: Bool { messageIndex >= Self.messageCount }

    public func handshakeHash() -> [UInt8] { symmetric.handshakeHash }

    /// Builds message 1 (`-> e, es`) with `payload` encrypted inside it.
    public mutating func writeMessage(payload: [UInt8]) throws -> [UInt8] {
        guard !isComplete, !finished else { throw NoiseError.handshakeComplete }
        guard messageIndex % 2 == 0 else { throw NoiseError.handshakeOutOfTurn }
        guard let remoteStatic else { throw NoiseError.missingKey("remote static key") }

        let keyPair = ephemeral ?? NoiseKeyPair.random()
        ephemeral = keyPair
        var message = keyPair.publicKey
        symmetric.mixHash(keyPair.publicKey)
        try symmetric.mixKey(Self.dh(secretKey: keyPair.secretKey, publicKey: remoteStatic))
        message += try symmetric.encryptAndHash(payload)
        try Self.checkMessageSize(message)
        messageIndex += 1
        return message
    }

    /// Consumes message 2 (`<- e, ee`) and returns its payload.
    public mutating func readMessage(_ message: [UInt8]) throws -> [UInt8] {
        try Self.checkMessageSize(message)
        guard !isComplete, !finished else { throw NoiseError.handshakeComplete }
        guard messageIndex % 2 == 1 else { throw NoiseError.handshakeOutOfTurn }
        guard let localEphemeral = ephemeral else { throw NoiseError.missingKey("local ephemeral") }
        guard message.count >= Self.dhByteCount else { throw NoiseError.invalidPublicKey }

        let remoteEphemeral = Array(message.prefix(Self.dhByteCount))
        self.remoteEphemeral = remoteEphemeral
        symmetric.mixHash(remoteEphemeral)
        try symmetric.mixKey(
            Self.dh(secretKey: localEphemeral.secretKey, publicKey: remoteEphemeral))
        let payload = try symmetric.decryptAndHash(Array(message.dropFirst(Self.dhByteCount)))
        messageIndex += 1
        return payload
    }

    /// Both handshake messages processed: derive the transport keys, send first.
    public mutating func split() throws -> (send: NoiseCipherState, receive: NoiseCipherState) {
        guard isComplete else { throw NoiseError.handshakeIncomplete }
        guard !finished else { throw NoiseError.handshakeComplete }
        finished = true
        let (first, second) = symmetric.split()
        ephemeral = nil
        remoteEphemeral = nil
        return (send: NoiseCipherState(key: first), receive: NoiseCipherState(key: second))
    }

    // MARK: X25519

    /// One DH, refusing low-order results. swift-crypto throws for invalid peer keys on some
    /// platforms and returns zeros on none, so check both.
    static func dh(secretKey: [UInt8], publicKey: [UInt8]) throws -> [UInt8] {
        guard secretKey.count == dhByteCount else {
            throw NoiseError.invalidKeyLength("secret key must be 32 bytes")
        }
        guard publicKey.count == dhByteCount else {
            throw NoiseError.invalidKeyLength("public key must be 32 bytes")
        }
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey)
        let peer: Curve25519.KeyAgreement.PublicKey
        do {
            peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw NoiseError.invalidPublicKey
        }
        let shared: SharedSecret
        do {
            shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        } catch {
            throw NoiseError.invalidPublicKey
        }
        let bytes = shared.withUnsafeBytes { Array($0) }
        guard bytes.contains(where: { $0 != 0 }) else { throw NoiseError.invalidPublicKey }
        return bytes
    }

    private static func checkMessageSize(_ message: [UInt8]) throws {
        guard message.count <= maxMessageBytes else { throw NoiseError.messageTooLarge }
    }
}

// MARK: - SymmetricState

/// Noise spec §5.2 for SHA-256 (HASHLEN 32).
private struct SymmetricState {
    private static let hashByteCount = 32
    private static let empty = [UInt8]()

    private var cipher: NoiseCipherState
    private var chainingKey: [UInt8]
    private var hash: [UInt8]

    init(protocolName: String) {
        let name = Array(protocolName.utf8)
        if name.count <= Self.hashByteCount {
            var padded = name
            padded += [UInt8](repeating: 0, count: Self.hashByteCount - name.count)
            hash = padded
        } else {
            hash = Self.sha256(name)
        }
        chainingKey = hash
        cipher = NoiseCipherState(key: nil)
    }

    var handshakeHash: [UInt8] { hash }

    mutating func mixHash(_ data: [UInt8]) {
        hash = Self.sha256(hash + data)
    }

    mutating func mixKey(_ inputKeyMaterial: [UInt8]) throws {
        let (chainingKey, tempKey) = Self.hkdf2(chainingKey: chainingKey, inputKeyMaterial: inputKeyMaterial)
        self.chainingKey = chainingKey
        cipher = NoiseCipherState(key: tempKey)
    }

    mutating func encryptAndHash(_ plaintext: [UInt8]) throws -> [UInt8] {
        let ciphertext = try cipher.encrypt(plaintext: plaintext, authenticating: hash)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: [UInt8]) throws -> [UInt8] {
        let plaintext: [UInt8]
        do {
            plaintext = try cipher.decrypt(ciphertext: ciphertext, authenticating: hash)
        } catch {
            throw NoiseError.authenticationFailed
        }
        mixHash(ciphertext)
        return plaintext
    }

    mutating func split() -> ([UInt8], [UInt8]) {
        let (first, second) = Self.hkdf2(chainingKey: chainingKey, inputKeyMaterial: Self.empty)
        chainingKey = [UInt8](repeating: 0, count: chainingKey.count)
        cipher.clear()
        return (first, second)
    }

    private static func sha256(_ data: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    /// Noise §4.3: HMAC chain with 0x01 and 0x02. This is HKDF with the chaining key as salt and
    /// empty info, which is why `HKDF<SHA256>` gives the same two keys in R17's transport.
    private static func hkdf2(chainingKey: [UInt8], inputKeyMaterial: [UInt8]) -> ([UInt8], [UInt8]) {
        let tempKey = SymmetricKey(
            data: HMAC<SHA256>.authenticationCode(
                for: inputKeyMaterial, using: SymmetricKey(data: chainingKey)))
        let first = Array(HMAC<SHA256>.authenticationCode(for: [0x01], using: tempKey))
        let second = Array(HMAC<SHA256>.authenticationCode(for: first + [0x02], using: tempKey))
        return (first, second)
    }
}
