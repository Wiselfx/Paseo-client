import Foundation
import Testing
@testable import PaseoStore

/// P5-B: `RichContentDetector.splitIntoBlocks` splits assistant prose into
/// block-level units so a streamed token re-parses only the open unit
/// (upstream `f35b0b8b7`). These tests pin the boundaries: blank lines split,
/// fences/SVGs/loose lists stay whole, and per-unit detection equals
/// whole-source detection.
@Suite struct SplitIntoBlocksTests {
    private func split(_ source: String) -> [Range<String.Index>] {
        RichContentDetector.splitIntoBlocks(source)
    }

    private func pieces(_ source: String) -> [String] {
        split(source).map { String(source[$0]) }
    }

    // MARK: Boundaries

    @Test func emptyAndWhitespaceOnlySourcesYieldNoRanges() {
        #expect(split("").isEmpty)
        #expect(split(" \n \n").isEmpty)
    }

    @Test func singleParagraphIsOneUnit() {
        #expect(pieces("Hello world") == ["Hello world"])
        #expect(split("Hello world").count == 1)
        #expect(split("Hello world").first == "Hello world".startIndex ..< "Hello world".endIndex)
    }

    @Test func blankLineSplitsTwoParagraphs() {
        #expect(pieces("First\n\nSecond") == ["First\n\n", "Second"])
        #expect(pieces("First\n\n\nSecond") == ["First\n\n\n", "Second"])
        #expect(pieces("\n\nFirst\n\nSecond") == ["First\n\n", "Second"])
    }

    @Test func headingAndParagraphSplit() {
        #expect(pieces("# Title\n\nParagraph") == ["# Title\n\n", "Paragraph"])
    }

    @Test func fencedCodeBlockStaysWhole() {
        #expect(pieces("```ts\nconst a = 1\n\nconst b = 2\n```") == ["```ts\nconst a = 1\n\nconst b = 2\n```"])
        #expect(pieces("Before\n\n~~~\ncode\n\nmore\n~~~\n\nAfter").count == 3)
    }

    @Test func unclosedFenceRunsToEndOfSource() {
        #expect(pieces("Before\n\n```ts\ncode\n\nmore") == ["Before\n\n", "```ts\ncode\n\nmore"])
    }

    @Test func looseListStaysWhole() {
        #expect(pieces("- a\n\n- b") == ["- a\n\n- b"])
        #expect(pieces("1. a\n\n2. b") == ["1. a\n\n2. b"])
        #expect(pieces("- a\n\n  - b") == ["- a\n\n  - b"])
    }

    @Test func listContinuationParagraphStaysWhole() {
        #expect(pieces("- a\n\n  continued") == ["- a\n\n  continued"])
    }

    @Test func looseListBetweenParagraphsStaysWhole() {
        #expect(pieces("Text\n\n- a\n\n- b\n\nMore") == ["Text\n\n", "- a\n\n- b\n\n", "More"])
    }

    @Test func nestedListStaysWhole() {
        #expect(pieces("Text\n\n- a\n  - b\n\nMore") == ["Text\n\n", "- a\n  - b\n\n", "More"])
    }

    @Test func listEndedByTopLevelParagraphSplits() {
        #expect(pieces("- a\n\nAfter") == ["- a\n\n", "After"])
        #expect(pieces("Text\n\n- a\n- b\n\nAfter") == ["Text\n\n", "- a\n- b\n\n", "After"])
    }

    @Test func rawSVGStaysWhole() {
        #expect(pieces("<svg>\n\n<circle/>\n\n</svg>\n\nAfter").first == "<svg>\n\n<circle/>\n\n</svg>\n\n")
        #expect(pieces("<svg>\n\n<circle/>\n\n</svg>\n\nAfter").count == 2)
    }

    @Test func blockquoteParagraphsSplitAtBlankLines() {
        // `>` blank lines are not blank, so the quote stays whole.
        #expect(pieces("> a\n>\n> b\n\nAfter") == ["> a\n>\n> b\n\n", "After"])
    }

    @Test func svgInsideAFenceIsNotTrackedAsSVG() {
        // A `<svg>` in a code sample is body text; it must not swallow the rest of
        // the document into one unit.
        #expect(pieces("```ts\n<svg>\n```\n\nAfter").count == 2)
    }

    @Test func rangesAreOrderedAndGapsAreBlank() {
        let source = "First\n\n```ts\ncode\n```\n\n- a\n- b\n\nAfter"
        let ranges = split(source)
        #expect(ranges.count == 4)
        #expect(ranges.first?.lowerBound == source.startIndex)
        #expect(ranges.last?.upperBound == source.endIndex)
        for (earlier, later) in zip(ranges, ranges.dropFirst()) {
            #expect(earlier.upperBound <= later.lowerBound)
            #expect(source[earlier.upperBound ..< later.lowerBound].allSatisfy { $0.isWhitespace })
        }
    }

    // MARK: Streaming stability

    @Test func appendingToTheOpenUnitLeavesEarlierUnitsUntouched() {
        let base = "First paragraph.\n\nSecond paragraph"
        let extended = base + " keeps growing, token by token"
        let before = split(base)
        let after = split(extended)
        #expect(before.count == 2)
        #expect(after.count == 2)
        #expect(after.first == before.first)
        #expect(after.last?.lowerBound == before.last?.lowerBound)
    }

    @Test func newParagraphAppendsAUnitWithoutMovingEarlierOnes() {
        let base = "First paragraph.\n\nSecond"
        let extended = base + "\n\nThird"
        let before = split(base)
        let after = split(extended)
        #expect(after.count == 3)
        #expect(after.first == before.first)
        #expect(after[1].lowerBound == before[1].lowerBound)
        #expect(String(extended[after[1]]) == "Second\n\n")
        #expect(String(extended[after[2]]) == "Third")
    }

    // MARK: Detection equivalence

    /// Per-unit detection must find exactly the blocks whole-source detection finds
    /// (same kind, same source text at the range), in document order.
    @Test func perUnitDetectionMatchesWholeSourceDetection() {
        let samples = [
            "Hello world",
            "First\n\nSecond",
            "```ts\nconst a = 1\n\nconst b = 2\n```",
            "Before\n\n```ts\ncode\n```\n\nAfter",
            "```visualize\n<div>\n\n</div>\n```\n\nAfter",
            "https://example.com/some/page\n\nText",
            "see https://example.com/x for details\n\nMore",
            "- https://example.com/x\n- b\n\nAfter",
            "![alt](/Users/x/photo.png)\n\nText",
            "/Users/x/photo.png\n\nText",
            "<svg>\n\n<circle/>\n\n</svg>\n\nAfter",
            "> quote\n>\n> more\n\nAfter",
            "37.7749, -122.4194\n\nText",
            "```youtube\ndQw4w9WgXcQ\n```\n\nAfter",
        ]
        for source in samples {
            var perUnit: [String] = []
            for range in split(source) {
                let unit = String(source[range])
                perUnit += signature(RichContentDetector.detect(in: unit), in: unit)
            }
            #expect(
                perUnit == signature(RichContentDetector.detect(in: source), in: source),
                "per-unit detection differs for \(source.debugDescription)")
        }
    }

    private func signature(_ blocks: [RichContentBlock], in source: String) -> [String] {
        blocks.map { block in
            let kind: String
            switch block {
            case .linkCard: kind = "linkCard"
            case .youTubePlayer: kind = "youTubePlayer"
            case .youTubeInline: kind = "youTubeInline"
            case .bareImageURL: kind = "bareImageURL"
            case .localImage: kind = "localImage"
            case .localFileLink: kind = "localFileLink"
            case .rawSVG: kind = "rawSVG"
            case .visualize: kind = "visualize"
            case .mermaid: kind = "mermaid"
            case .imageGroup: kind = "imageGroup"
            case .mapCard: kind = "mapCard"
            }
            return "\(kind):\(source[block.range])"
        }
    }
}
