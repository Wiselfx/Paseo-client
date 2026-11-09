import PaseoKit
import Testing
@testable import PaseoStore

/// R18 item 6 / review NIT 2: relay upload chunk sizing vs the relay caps.
@Suite @MainActor struct RelayUploadCapTests {
    @Test func relayChunksStayUnderTheRelayBound() {
        let chunk = ConversationUpload.chunkSize(relay: true)
        #expect(chunk == 1 * 1024 * 1024)
        // The bound is the test's subject, not one-record-per-frame: the whole chunk's
        // plaintext must fit the 25 MB relay plaintext ceiling comfortably.
        #expect(PaseoKit.RelayRecordCodec.maxPlaintextByteLength(wireBytes: 32 * 1024 * 1024) >= chunk)
        let wire = PaseoKit.RelayRecordCodec.protectedRecordByteLength(chunk)
        #expect(wire < 32 * 1024 * 1024)
        // 1 MiB chunks keep a 50 MB upload to ~50 binary frames.
        #expect(ConversationUpload.maxBytes / chunk <= 50)
    }

    @Test func directChunksKeepUpstreamSize() {
        #expect(ConversationUpload.chunkSize(relay: false) == 128 * 1024)
    }
}
