import PaseoKit
import Testing
@testable import PaseoStore

/// R18 item 6: relay upload chunk sizing vs the relay caps.
@Suite @MainActor struct RelayUploadCapTests {
    @Test func relayChunksStayUnderEveryRelayCap() {
        let chunk = ConversationUpload.chunkSize(relay: true)
        #expect(chunk <= PaseoKit.RelayRecordCodec.maxChunkDataBytes)
        #expect(PaseoKit.RelayRecordCodec.chunkCount(chunk) == 1, "one record per binary frame")
        let wire = PaseoKit.RelayRecordCodec.protectedRecordByteLength(chunk)
        #expect(wire < 32 * 1024 * 1024, "far under the relay's 32 MiB per-message limit")
        #expect(PaseoKit.RelayRecordCodec.maxPlaintextByteLength(wireBytes: 32 * 1024 * 1024) >= chunk)
    }

    @Test func directChunksKeepUpstreamSize() {
        #expect(ConversationUpload.chunkSize(relay: false) == 128 * 1024)
    }
}
