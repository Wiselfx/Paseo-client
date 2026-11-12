import Foundation
import Testing

@testable import PaseoStore

// G11 C3/C4: standalone media paths and URLs become player cards.
struct RichStandaloneMediaTests {
    private func blocks(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    @Test("standalone local video and audio paths match with kinds")
    func localMediaMatches() {
        #expect(
            RichStandaloneMedia.match(blocks: blocks("/tmp/clip.mp4"), unitText: "/tmp/clip.mp4")
                == .local(path: "/tmp/clip.mp4", kind: .video))
        #expect(
            RichStandaloneMedia.match(blocks: blocks("~/voice.M4A"), unitText: "  ~/voice.M4A\n")
                == .local(path: "~/voice.M4A", kind: .audio))
    }

    @Test("standalone remote media URLs match, query strings ignored")
    func remoteMediaMatches() {
        #expect(
            RichStandaloneMedia.match(
                blocks: blocks("https://example.com/r.mp4"), unitText: "https://example.com/r.mp4")
                == .remote(url: "https://example.com/r.mp4", kind: .video))
        #expect(
            RichStandaloneMedia.match(
                blocks: blocks("https://example.com/a/aiff?a=b"),
                unitText: "https://example.com/a/aiff?a=b") == nil)
    }

    @Test(".webm stays a file, images are not media")
    func webmAndImagesExcluded() {
        #expect(RichStandaloneMedia.match(blocks: blocks("/tmp/clip.webm"), unitText: "/tmp/clip.webm") == nil)
        #expect(RichStandaloneMedia.match(blocks: blocks("/tmp/shot.png"), unitText: "/tmp/shot.png") == nil)
        #expect(RichStandaloneMedia.match(blocks: blocks("https://example.com/a.png"), unitText: "https://example.com/a.png") == nil)
    }

    @Test("inline mentions and multi-block units do not match")
    func inlineDoesNotMatch() {
        #expect(RichStandaloneMedia.match(blocks: blocks("see /tmp/clip.mp4 ok"), unitText: "see /tmp/clip.mp4 ok") == nil)
        #expect(RichStandaloneMedia.match(blocks: blocks("https://example.com/a https://example.com/b.mp4"), unitText: "x") == nil)
    }

    @Test("extension table")
    func extensionTable() {
        #expect(RichStandaloneMedia.kindForPath("a.MP4") == .video)
        #expect(RichStandaloneMedia.kindForPath("a.webm") == nil)
        #expect(RichStandaloneMedia.kindForPath("a.pdf") == nil)
        #expect(RichStandaloneMedia.kindForPath("a") == nil)
    }
}
