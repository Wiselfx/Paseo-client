import Foundation
import Testing

@testable import PaseoStore

// G7 C2: adjacent image blocks separated only by blank lines group into one card.
struct RichImageGroupingTests {
    private func image(_ url: String) -> RichContentBlock {
        .bareImageURL(url: url, range: url.startIndex..<url.endIndex)
    }

    private func local(_ path: String) -> RichContentBlock {
        .localImage(path: path, alt: "", range: path.startIndex..<path.endIndex)
    }

    private func link(_ url: String) -> RichContentBlock {
        .linkCard(url: url, range: url.startIndex..<url.endIndex)
    }

    @Test("two adjacent images group, whatever the blank between them")
    func adjacentImagesGroup() {
        for separator in ["", "\n", "\n\n", "  \n  \n "] {
            #expect(RichImageGrouping.continuesRun(
                next: image("b"), after: image("a"), separatorIsBlank: separator.allSatisfy(\.isWhitespace)))
        }
        #expect(RichImageGrouping.continuesRun(
            next: local("/tmp/b.png"), after: image("https://example.com/a.png"),
            separatorIsBlank: true))
    }

    @Test("prose or other blocks break the run")
    func nonBlankBreaksRun() {
        #expect(!RichImageGrouping.continuesRun(
            next: image("b"), after: image("a"), separatorIsBlank: false))
        #expect(!RichImageGrouping.continuesRun(
            next: link("https://example.com"), after: image("a"), separatorIsBlank: true))
        #expect(!RichImageGrouping.continuesRun(
            next: image("b"), after: link("https://example.com"), separatorIsBlank: true))
    }

    @Test("group keeps document order and spans the run")
    func groupSpansRun() {
        let source = "x"
        let block = RichImageGrouping.group(
            images: [
                RichImage(source: .remote(url: "a"), alt: ""),
                RichImage(source: .local(path: "b"), alt: "B"),
            ],
            range: source.startIndex..<source.endIndex)
        guard case .imageGroup(let images, _) = block else {
            Issue.record("expected .imageGroup")
            return
        }
        #expect(images.map(\.alt) == ["", "B"])
    }

    @Test("SVG sources stay out: they keep their own vector card")
    func svgStaysOut() {
        let svg = RichContentBlock.rawSVG(source: "<svg></svg>", range: "x".startIndex..<"x".endIndex)
        #expect(RichImage.of(block: svg) == nil)
        #expect(RichImage.of(block: image("https://example.com/d.svg")) == nil)
        #expect(RichImage.of(block: local("/tmp/d.svg")) == nil)
        #expect(RichImage.of(block: image("https://example.com/d.png")) != nil)
    }

    @Test("the detector itself never groups: grouping is the splice's job")
    func detectorLeavesSingles() {
        // Two adjacent bare URLs stay two blocks at detection time (the contract
        // existing tests pin); `RichImageGrouping` merges them afterwards.
        let blocks = RichContentDetector.detect(in: "https://example.com/a.png\nhttps://example.com/b.png")
        #expect(blocks.count == 2)
    }
}
