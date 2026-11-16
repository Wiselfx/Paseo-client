import Foundation

// Authenticated application-frame framing over relay transport records.
// Spec: docs/research/11-relay-pairing.md §4.2; upstream `packages/relay/src/protected-records.ts`.
//
// One application frame becomes one wire record of one or more Noise messages. The frame kind,
// the FIRST/FINAL flags and the total frame length travel *inside* the authenticated plaintext, so
// an untrusted relay cannot merge two records, split one, truncate a final chunk or re-chunk a
// frame without the receiver noticing.
//
//   chunk plaintext = kind(1) || flags(1) || totalLength(u32 BE) || data
//   wire record     = for each chunk: ciphertextLength(u16 BE) || ciphertext

public enum RelayFrameKind: Sendable, Equatable {
    case text
    case binary
}

/// Every way a record can be refused. Each one closes the channel; nothing partial is delivered.
public enum RelayRecordError: Error, Equatable, Sendable {
    case emptyRecord
    case truncated
    case invalidChunkLength
    case doesNotStartWithFirst
    case firstRepeated
    case frameKindChanged
    case frameLengthChanged
    case finalFlagMismatch
    case chunkSizeMismatch
    case recordLengthMismatch
    case trailingBytes
    case invalidFrameKind
    case reservedFlag
    case incomplete
    case frameTooLarge
}

/// One decoded application frame: the WebSocket opcode it must be delivered as, and its bytes.
public struct RelayDecodedFrame: Sendable, Equatable {
    public var kind: RelayFrameKind
    public var data: [UInt8]

    public init(kind: RelayFrameKind, data: [UInt8]) {
        self.kind = kind
        self.data = data
    }
}

/// Framing rules and the chunk format. Every rejection closes the channel; nothing partial is
/// ever returned.
public enum RelayRecordCodec {
    /// One Noise message holds at most 65535 bytes: 6 header + data + 16 tag.
    public static let maxChunkDataBytes = NoiseNK.maxMessageBytes - NoiseCipherState.tagByteCount - headerByteCount
    /// Largest frame the format can describe (`u32` length field).
    public static let maxFrameBytes: Int = 0xFFFF_FFFF
    /// `u16` length prefix + chunk header + AEAD tag.
    static let chunkOverheadBytes = lengthPrefixByteCount + headerByteCount + NoiseCipherState.tagByteCount

    private static let headerByteCount = 6
    private static let lengthPrefixByteCount = 2
    private static let kindText: UInt8 = 0x00
    private static let kindBinary: UInt8 = 0x01
    private static let flagFirst: UInt8 = 0x01
    private static let flagFinal: UInt8 = 0x02
    private static let knownFlags: UInt8 = flagFirst | flagFinal
    private static let emptyAD = [UInt8]()

    /// Chunks a frame of `frameBytes` needs. Never zero, even for an empty frame.
    public static func chunkCount(_ frameBytes: Int) -> Int {
        max(1, (frameBytes + maxChunkDataBytes - 1) / maxChunkDataBytes)
    }

    /// Wire bytes a frame occupies once protected.
    public static func protectedRecordByteLength(_ frameBytes: Int) -> Int {
        frameBytes + chunkCount(frameBytes) * chunkOverheadBytes
    }

    /// Largest plaintext that fits in `wireBytes` of base64 text in either security mode. Callers
    /// size payloads before the mode is known, so take the tighter of the two bounds.
    public static func maxPlaintextByteLength(wireBytes: Int) -> Int {
        // Legacy: 24-byte nonce + 16-byte tag, then base64.
        let legacyBound = (wireBytes / 4) * 3 - (24 + NoiseCipherState.tagByteCount)
        let base64Capacity = (wireBytes / 4) * 3
        var protectedBound = base64Capacity
        while protectedBound > 0, protectedRecordByteLength(protectedBound) > base64Capacity {
            protectedBound = base64Capacity - (protectedRecordByteLength(protectedBound) - protectedBound)
        }
        return max(0, min(legacyBound, protectedBound))
    }

    /// Protects one application frame. The sender's nonce is reserved synchronously, so the caller
    /// must not share a cipher state between writers.
    public static func encode(
        kind: RelayFrameKind, frame: [UInt8], sender: inout NoiseCipherState
    ) throws -> [UInt8] {
        guard frame.count <= maxFrameBytes else { throw RelayRecordError.frameTooLarge }
        let chunks = chunkCount(frame.count)
        var record = [UInt8]()
        record.reserveCapacity(protectedRecordByteLength(frame.count))
        for index in 0..<chunks {
            let start = index * maxChunkDataBytes
            let end = min(frame.count, start + maxChunkDataBytes)
            var plaintext = [UInt8]()
            plaintext.reserveCapacity(headerByteCount + (end - start))
            plaintext.append(kind == .text ? kindText : kindBinary)
            var flags: UInt8 = 0
            if index == 0 { flags |= flagFirst }
            if index == chunks - 1 { flags |= flagFinal }
            plaintext.append(flags)
            appendUInt32(UInt32(frame.count), to: &plaintext)
            plaintext.append(contentsOf: frame[start..<end])
            let ciphertext = try sender.encrypt(plaintext: plaintext, authenticating: emptyAD)
            guard ciphertext.count <= Int(UInt16.max) else {
                throw RelayRecordError.invalidChunkLength
            }
            record.append(UInt8(truncatingIfNeeded: ciphertext.count >> 8))
            record.append(UInt8(truncatingIfNeeded: ciphertext.count))
            record.append(contentsOf: ciphertext)
        }
        return record
    }

    /// Decodes one wire record. Chunks are authenticated in order and the receive counter advances
    /// per authenticated chunk; any framing violation throws and the caller must close.
    public static func decode(_ record: [UInt8], receiver: inout NoiseCipherState) throws
        -> RelayDecodedFrame
    {
        guard !record.isEmpty else { throw RelayRecordError.emptyRecord }
        var offset = 0
        var assembly: Assembly?
        while offset < record.count {
            if let current = assembly, current.index >= current.expectedChunks {
                throw RelayRecordError.trailingBytes
            }
            let (chunk, next) = try readChunk(record, offset: offset, receiver: &receiver)
            offset = next
            if let current = assembly {
                assembly = try continueAssembly(current, chunk: chunk)
            } else {
                assembly = try startAssembly(chunk, recordByteLength: record.count)
            }
        }
        guard let assembly else { throw RelayRecordError.emptyRecord }
        guard assembly.index == assembly.expectedChunks, assembly.written == assembly.totalLength
        else { throw RelayRecordError.incomplete }
        return RelayDecodedFrame(kind: assembly.kind, data: assembly.frame)
    }

    // MARK: Chunks

    private struct Chunk {
        var kind: RelayFrameKind
        var isFirst: Bool
        var isFinal: Bool
        var totalLength: Int
        var data: [UInt8]
    }

    private struct Assembly {
        var kind: RelayFrameKind
        var totalLength: Int
        var expectedChunks: Int
        var frame: [UInt8]
        var written: Int
        var index: Int
    }

    private static func readChunk(
        _ record: [UInt8], offset: Int, receiver: inout NoiseCipherState
    ) throws -> (Chunk, Int) {
        guard record.count - offset >= lengthPrefixByteCount else {
            throw RelayRecordError.truncated
        }
        let ciphertextLength = Int(readUInt16(record, offset))
        let start = offset + lengthPrefixByteCount
        guard ciphertextLength >= NoiseCipherState.tagByteCount + headerByteCount,
            ciphertextLength <= NoiseNK.maxMessageBytes
        else { throw RelayRecordError.invalidChunkLength }
        guard record.count - start >= ciphertextLength else {
            throw RelayRecordError.truncated
        }
        let plaintext = try receiver.decrypt(
            ciphertext: Array(record[start..<(start + ciphertextLength)]), authenticating: emptyAD)
        guard plaintext.count >= headerByteCount else { throw RelayRecordError.truncated }
        let flags = plaintext[1]
        guard flags & ~knownFlags == 0 else { throw RelayRecordError.reservedFlag }
        guard let kind = decodeKind(plaintext[0]) else { throw RelayRecordError.invalidFrameKind }
        return (
            Chunk(
                kind: kind,
                isFirst: flags & flagFirst != 0,
                isFinal: flags & flagFinal != 0,
                totalLength: Int(readUInt32(plaintext, 2)),
                data: Array(plaintext.dropFirst(headerByteCount))),
            start + ciphertextLength
        )
    }

    private static func startAssembly(_ chunk: Chunk, recordByteLength: Int) throws -> Assembly {
        guard chunk.isFirst else { throw RelayRecordError.doesNotStartWithFirst }
        // The claimed length fixes the record's exact wire length. Check it before allocating, so
        // an authenticated header cannot demand gigabytes.
        guard protectedRecordByteLength(chunk.totalLength) == recordByteLength else {
            throw RelayRecordError.recordLengthMismatch
        }
        return try append(
            Assembly(
                kind: chunk.kind,
                totalLength: chunk.totalLength,
                expectedChunks: chunkCount(chunk.totalLength),
                frame: [UInt8](repeating: 0, count: chunk.totalLength),
                written: 0,
                index: 0),
            chunk: chunk)
    }

    private static func continueAssembly(_ assembly: Assembly, chunk: Chunk) throws -> Assembly {
        guard !chunk.isFirst else { throw RelayRecordError.firstRepeated }
        guard chunk.kind == assembly.kind else { throw RelayRecordError.frameKindChanged }
        guard chunk.totalLength == assembly.totalLength else {
            throw RelayRecordError.frameLengthChanged
        }
        return try append(assembly, chunk: chunk)
    }

    private static func append(_ assembly: Assembly, chunk: Chunk) throws -> Assembly {
        var assembly = assembly
        let isLastExpected = assembly.index == assembly.expectedChunks - 1
        guard chunk.isFinal == isLastExpected else { throw RelayRecordError.finalFlagMismatch }
        let expectedData =
            isLastExpected
            ? assembly.totalLength - assembly.index * maxChunkDataBytes
            : maxChunkDataBytes
        guard chunk.data.count == expectedData else { throw RelayRecordError.chunkSizeMismatch }
        assembly.frame.replaceSubrange(
            assembly.written..<(assembly.written + chunk.data.count), with: chunk.data)
        assembly.written += chunk.data.count
        assembly.index += 1
        return assembly
    }

    private static func decodeKind(_ byte: UInt8) -> RelayFrameKind? {
        switch byte {
        case kindText: return .text
        case kindBinary: return .binary
        default: return nil
        }
    }

    // MARK: Big-endian fields

    private static func appendUInt32(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value))
    }

    private static func readUInt16(_ source: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(source[offset]) << 8 | UInt16(source[offset + 1])
    }

    private static func readUInt32(_ source: [UInt8], _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value = value << 8 | UInt32(source[offset + index])
        }
        return value
    }
}
