import Foundation
import Testing

@testable import PaseoStore

// G4 (C9, D2): a closed ```mermaid fence is a diagram block. A streaming (unclosed)
// fence stays a code block — the half-written diagram never flashes or errors.
struct MermaidDetectorTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    /// C9 — a closed fence with a body detects, carrying the source and the range.
    @Test func closedFenceDetects() throws {
        let source = "```mermaid\ngraph TD; A-->B\n```"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .mermaid(let found, let range) = blocks[0] else {
            Issue.record("expected .mermaid, got \(blocks[0])")
            return
        }
        #expect(found == "graph TD; A-->B")
        #expect(source[range] == source[source.startIndex...])
    }

    /// C9 — info matching is case-insensitive and trims whitespace, like the other fences.
    @Test func infoCaseIsIgnored() throws {
        let blocks = detected("```Mermaid\ngraph TD; A-->B\n```")
        try #require(blocks.count == 1)
        guard case .mermaid = blocks[0] else {
            Issue.record("expected .mermaid, got \(blocks[0])")
            return
        }
    }

    /// C9 — a blank body renders nothing, like the visualize fence.
    @Test func blankBodyYieldsNothing() {
        #expect(detected("```mermaid\n   \n```").isEmpty)
        #expect(detected("```mermaid\n```").isEmpty)
    }

    /// C9 — unclosed fences stay code: the streaming diagram never flashes or errors.
    @Test func streamingFenceYieldsNothing() {
        #expect(detected("```mermaid\ngraph TD; A-->B\n").isEmpty)
        #expect(detected("```mermaid").isEmpty)
    }

    /// C9 — fence contents are protected zones: URLs inside never become link cards.
    @Test func fenceContentsAreNotScanned() throws {
        let blocks = detected("```mermaid\ngraph TD; A-->https://example.com/x\n```")
        try #require(blocks.count == 1)
        guard case .mermaid = blocks[0] else {
            Issue.record("expected .mermaid, got \(blocks[0])")
            return
        }
    }

    /// C9 — document order holds against the neighbouring blocks.
    @Test func documentOrderHolds() throws {
        let blocks = detected(
            "https://example.com/a\n\n```mermaid\ngraph TD; A-->B\n```\n\nhttps://example.com/b")
        try #require(blocks.count == 3)
        guard case .linkCard = blocks[0] else { Issue.record(); return }
        guard case .mermaid = blocks[1] else { Issue.record(); return }
        guard case .linkCard = blocks[2] else { Issue.record(); return }
    }
}
