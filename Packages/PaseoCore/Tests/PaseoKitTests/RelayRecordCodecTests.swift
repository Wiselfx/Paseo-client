import Foundation
import Testing
@testable import PaseoKit

/// R16: record framing, `kind(1) || flags(1) || totalLength(u32 BE) || data` inside Noise
/// messages, `(u16 length || ciphertext)+` on the wire. Every rule in the daemon's
/// `protected-records.ts` has a case here.
@Suite struct RelayRecordCodecTests {
    /// Key derivation is covered by the NK vector tests; framing is independent of it, so a fixed
    /// key keeps these cases about framing only.
    private func makeStates() -> (sender: NoiseCipherState, receiver: NoiseCipherState) {
        let key = [UInt8](repeating: 0x2A, count: 32)
        return (NoiseCipherState(key: key), NoiseCipherState(key: key))
    }

    // MARK: Round trips

    @Test func textFramesRoundTrip() throws {
        var (sender, receiver) = makeStates()
        let frame = Array("{\"type\":\"hello\"}".utf8)
        let record = try RelayRecordCodec.encode(kind: .text, frame: frame, sender: &sender)
        #expect(record.count == RelayRecordCodec.protectedRecordByteLength(frame.count))
        let decoded = try RelayRecordCodec.decode(record, receiver: &receiver)
        #expect(decoded == RelayDecodedFrame(kind: .text, data: frame))
    }

    @Test func binaryFramesRoundTrip() throws {
        var (sender, receiver) = makeStates()
        let frame: [UInt8] = (0..<200).map { UInt8($0 % 256) }
        let record = try RelayRecordCodec.encode(kind: .binary, frame: frame, sender: &sender)
        let decoded = try RelayRecordCodec.decode(record, receiver: &receiver)
        #expect(decoded == RelayDecodedFrame(kind: .binary, data: frame))
    }

    @Test func emptyFramesAreOneChunk() throws {
        var (sender, receiver) = makeStates()
        let record = try RelayRecordCodec.encode(kind: .text, frame: [], sender: &sender)
        #expect(RelayRecordCodec.chunkCount(0) == 1)
        #expect(record.count == RelayRecordCodec.protectedRecordByteLength(0))
        let decoded = try RelayRecordCodec.decode(record, receiver: &receiver)
        #expect(decoded == RelayDecodedFrame(kind: .text, data: []))
    }

    @Test func framesLargerThanOneNoiseMessageSplitAndReassemble() throws {
        let (baseSender, baseReceiver) = makeStates()
        for size in [
            RelayRecordCodec.maxChunkDataBytes,
            RelayRecordCodec.maxChunkDataBytes + 1,
            RelayRecordCodec.maxChunkDataBytes * 2 + 17,
        ] {
            var sender = baseSender
            var receiver = baseReceiver
            let frame = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31) }
            #expect(RelayRecordCodec.chunkCount(size) == (size + RelayRecordCodec.maxChunkDataBytes - 1) / RelayRecordCodec.maxChunkDataBytes)
            let record = try RelayRecordCodec.encode(kind: .binary, frame: frame, sender: &sender)
            #expect(record.count == RelayRecordCodec.protectedRecordByteLength(size))
            let decoded = try RelayRecordCodec.decode(record, receiver: &receiver)
            #expect(decoded.kind == .binary)
            #expect(decoded.data == frame)
        }
    }

    @Test func chunkGeometryMatchesTheWireFormat() {
        #expect(RelayRecordCodec.maxChunkDataBytes == 65_513)
        #expect(NoiseNK.maxMessageBytes == 65_535)
        #expect(RelayRecordCodec.protectedRecordByteLength(0) == 24)
        #expect(RelayRecordCodec.protectedRecordByteLength(10) == 34)
        #expect(RelayRecordCodec.protectedRecordByteLength(65_513) == 65_537)
        #expect(RelayRecordCodec.protectedRecordByteLength(65_514) == 65_562)
    }

    @Test func maximumRelayFrameFitsInTheRelayLimit() {
        // 32 MiB wire budget, as the relay enforces it: the plaintext capacity is the tighter of
        // the legacy and protected bounds.
        #expect(RelayRecordCodec.maxPlaintextByteLength(wireBytes: 32 * 1024 * 1024) == 25_156_584)
        #expect(RelayRecordCodec.maxPlaintextByteLength(wireBytes: 4) == 0)
    }

    // MARK: Nonce discipline

    @Test func theReceiverCounterAdvancesOnlyAfterTheTagVerifies() throws {
        var (sender, receiver) = makeStates()
        let first = try RelayRecordCodec.encode(kind: .text, frame: [1], sender: &sender)
        let second = try RelayRecordCodec.encode(kind: .text, frame: [2], sender: &sender)

        #expect(receiver.nextNonce == 0)
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try RelayRecordCodec.decode(second, receiver: &receiver)
        }
        #expect(receiver.nextNonce == 0)
        // The genuine next record still decrypts, and so does the one after it.
        #expect(try RelayRecordCodec.decode(first, receiver: &receiver).data == [1])
        #expect(try RelayRecordCodec.decode(second, receiver: &receiver).data == [2])
        #expect(receiver.nextNonce == 2)

        // A replay of an already-delivered record is refused, and does not move the counter
        // back, so the next genuine record still decrypts.
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try RelayRecordCodec.decode(first, receiver: &receiver)
        }
        #expect(receiver.nextNonce == 2)
        let third = try RelayRecordCodec.encode(kind: .text, frame: [3], sender: &sender)
        #expect(try RelayRecordCodec.decode(third, receiver: &receiver).data == [3])
    }

    @Test func aReflectedRecordIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RelayRecordCodec.encode(kind: .text, frame: [7], sender: &sender)
        // Same key both directions in this fixture, so reflection is the sender's own record fed
        // back as if it came from the peer: the nonce no longer matches, so the tag fails.
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try RelayRecordCodec.decode(record, receiver: &sender)
        }
        var freshReceiver = receiver
        #expect(try RelayRecordCodec.decode(record, receiver: &freshReceiver).data == [7])
    }

    @Test func outOfOrderRecordsAreRefusedAndNothingAdvances() throws {
        var (sender, receiver) = makeStates()
        let first = try RelayRecordCodec.encode(kind: .text, frame: [1], sender: &sender)
        let second = try RelayRecordCodec.encode(kind: .text, frame: [2], sender: &sender)
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try RelayRecordCodec.decode(second, receiver: &receiver)
        }
        #expect(receiver.nextNonce == 0)
        #expect(try RelayRecordCodec.decode(first, receiver: &receiver).data == [1])
        #expect(try RelayRecordCodec.decode(second, receiver: &receiver).data == [2])
    }

    @Test func theSenderCounterAdvancesPerChunkNotPerFrame() throws {
        var (sender, _) = makeStates()
        let frame = [UInt8](repeating: 3, count: RelayRecordCodec.maxChunkDataBytes + 1)
        #expect(sender.nextNonce == 0)
        _ = try RelayRecordCodec.encode(kind: .binary, frame: frame, sender: &sender)
        #expect(sender.nextNonce == 2)
    }

    // MARK: Malformed records

    @Test func anEmptyRecordIsRefused() {
        var (_, receiver) = makeStates()
        #expect(throws: RelayRecordError.emptyRecord) {
            _ = try RelayRecordCodec.decode([], receiver: &receiver)
        }
    }

    @Test func aTruncatedRecordIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RelayRecordCodec.encode(kind: .text, frame: [9, 9, 9], sender: &sender)
        for cut in [record.count - 1, record.count / 2, 1] {
            #expect(throws: RelayRecordError.truncated) {
                _ = try RelayRecordCodec.decode(Array(record.prefix(cut)), receiver: &receiver)
            }
        }
    }

    @Test func anInvalidChunkLengthIsRefused() throws {
        var (_, receiver) = makeStates()
        // A length shorter than a tag plus a header cannot be a chunk. (The upper bound in the
        // format is 65535, which a u16 cannot exceed, so only this side is reachable.)
        let tooShort: [UInt8] = [0x00, 0x10] + [UInt8](repeating: 0, count: 16)
        #expect(throws: RelayRecordError.invalidChunkLength) {
            _ = try RelayRecordCodec.decode(tooShort, receiver: &receiver)
        }
        // A maximum-length claim with nothing behind it is simply truncated.
        let claimsEverything: [UInt8] = [0xFF, 0xFF] + [UInt8](repeating: 0, count: 32)
        #expect(throws: RelayRecordError.truncated) {
            _ = try RelayRecordCodec.decode(claimsEverything, receiver: &receiver)
        }
    }

    @Test func aRecordThatDoesNotStartWithFirstIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RawChunk.record(
            [(0x00, 0x02, 1, [0x41])], sender: &sender)
        #expect(throws: RelayRecordError.doesNotStartWithFirst) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aRepeatedFirstFlagIsRefused() throws {
        var (sender, receiver) = makeStates()
        let chunkSize = RelayRecordCodec.maxChunkDataBytes
        let record = try RawChunk.record(
            [
                (0x01, 0x01, UInt32(chunkSize + 1), [UInt8](repeating: 0x41, count: chunkSize)),
                (0x01, 0x03, UInt32(chunkSize + 1), [0x42]),
            ], sender: &sender)
        #expect(throws: RelayRecordError.firstRepeated) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aFrameKindThatChangesInsideARecordIsRefused() throws {
        var (sender, receiver) = makeStates()
        let chunkSize = RelayRecordCodec.maxChunkDataBytes
        let total = chunkSize + 1
        let record = try RawChunk.record(
            [
                (0x00, 0x01, UInt32(total), [UInt8](repeating: 0x41, count: chunkSize)),
                (0x01, 0x02, UInt32(total), [0x42]),
            ], sender: &sender)
        #expect(throws: RelayRecordError.frameKindChanged) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aFrameLengthThatChangesInsideARecordIsRefused() throws {
        var (sender, receiver) = makeStates()
        let chunkSize = RelayRecordCodec.maxChunkDataBytes
        let total = chunkSize + 1
        let record = try RawChunk.record(
            [
                (0x00, 0x01, UInt32(total), [UInt8](repeating: 0x41, count: chunkSize)),
                (0x00, 0x02, UInt32(total + 1), [0x42]),
            ], sender: &sender)
        #expect(throws: RelayRecordError.frameLengthChanged) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aMissingFinalFlagIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RawChunk.record([(0x00, 0x01, 1, [0x41])], sender: &sender)
        #expect(throws: RelayRecordError.finalFlagMismatch) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aFinalOnANonFinalChunkIsRefused() throws {
        var (sender, receiver) = makeStates()
        let chunkSize = RelayRecordCodec.maxChunkDataBytes
        let total = chunkSize + 1
        let record = try RawChunk.record(
            [
                (0x00, 0x03, UInt32(total), [UInt8](repeating: 0x41, count: chunkSize)),
                (0x00, 0x02, UInt32(total), [0x42]),
            ], sender: &sender)
        #expect(throws: RelayRecordError.finalFlagMismatch) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aShortNonFinalChunkIsRefused() throws {
        var (sender, receiver) = makeStates()
        // Two chunks are due, and the record's wire length is right, but the first chunk is one
        // byte short of a full Noise message.
        let total = RelayRecordCodec.maxChunkDataBytes + 1
        let record = try RawChunk.record(
            [
                (0x00, 0x01, UInt32(total), [UInt8](repeating: 0x41, count: RelayRecordCodec.maxChunkDataBytes - 1)),
                (0x00, 0x02, UInt32(total), [0x42, 0x43]),
            ], sender: &sender)
        #expect(record.count == RelayRecordCodec.protectedRecordByteLength(total))
        #expect(throws: RelayRecordError.chunkSizeMismatch) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aRecordWhoseClaimedLengthDoesNotMatchTheWireIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RawChunk.record(
            [(0x00, 0x03, 1_000, [UInt8](repeating: 0x41, count: 1_000))], sender: &sender)
        let truncated = Array(record.prefix(record.count - 1))
        #expect(throws: RelayRecordError.truncated) {
            _ = try RelayRecordCodec.decode(truncated, receiver: &receiver)
        }
        // Claiming more bytes than the record carries is caught before any allocation.
        let (baseLyingSender, baseLyingReceiver) = makeStates()
        var lyingSender = baseLyingSender
        var lyingReceiver = baseLyingReceiver
        let lying = try RawChunk.record([(0x00, 0x03, 65_535, [0x41])], sender: &lyingSender)
        #expect(throws: RelayRecordError.recordLengthMismatch) {
            _ = try RelayRecordCodec.decode(lying, receiver: &lyingReceiver)
        }
    }

    @Test func bytesAppendedAfterAFinalChunkAreRefused() throws {
        var (sender, receiver) = makeStates()
        var record = try RelayRecordCodec.encode(kind: .text, frame: [1], sender: &sender)
        record += [0x00, 0x00]
        // The chunk's authenticated header pins the record's exact length, so appended bytes are
        // a length mismatch, not a second chunk. That check also makes the decoder's
        // "chunk after the final one" branch unreachable; it stays as defence in depth.
        #expect(throws: RelayRecordError.recordLengthMismatch) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func anInvalidFrameKindIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RawChunk.record([(0x02, 0x03, 1, [0x41])], sender: &sender)
        #expect(throws: RelayRecordError.invalidFrameKind) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aReservedFlagIsRefused() throws {
        var (sender, receiver) = makeStates()
        let record = try RawChunk.record([(0x00, 0x07, 1, [0x41])], sender: &sender)
        #expect(throws: RelayRecordError.reservedFlag) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func aTamperedChunkIsRefused() throws {
        var (sender, receiver) = makeStates()
        var record = try RelayRecordCodec.encode(kind: .text, frame: [1, 2, 3], sender: &sender)
        record[record.count - 1] ^= 0x01
        #expect(throws: NoiseError.authenticationFailed) {
            _ = try RelayRecordCodec.decode(record, receiver: &receiver)
        }
    }

    @Test func theFormatLimitIsTheUInt32LengthField() {
        // The 4 GiB guard itself cannot be exercised without a 4 GiB allocation.
        #expect(RelayRecordCodec.maxFrameBytes == Int(UInt32.max))
    }
}

/// Builds records chunk by chunk, so a test can put illegal metadata inside an authenticated
/// chunk and prove the decoder refuses it rather than the tag failing.
enum RawChunk {
    typealias Chunk = (kind: UInt8, flags: UInt8, totalLength: UInt32, data: [UInt8])

    static func record(_ chunks: [Chunk], sender: inout NoiseCipherState) throws -> [UInt8] {
        var record: [UInt8] = []
        for chunk in chunks {
            var plaintext: [UInt8] = [chunk.kind, chunk.flags]
            plaintext += [
                UInt8(truncatingIfNeeded: chunk.totalLength >> 24),
                UInt8(truncatingIfNeeded: chunk.totalLength >> 16),
                UInt8(truncatingIfNeeded: chunk.totalLength >> 8),
                UInt8(truncatingIfNeeded: chunk.totalLength),
            ]
            plaintext += chunk.data
            let ciphertext = try sender.encrypt(plaintext: plaintext)
            record += [UInt8(truncatingIfNeeded: ciphertext.count >> 8), UInt8(truncatingIfNeeded: ciphertext.count)]
            record += ciphertext
        }
        return record
    }
}
