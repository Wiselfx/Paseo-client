import Foundation
import Testing

@testable import PaseoStore

// V2.3: some models/providers HTML-escape their own output. The escaping is in the text we
// receive, so the five basic entities are decoded for artifact and diagram bodies only —
// never for prose or ordinary code blocks — and only when the whole body is escaped markup.
struct RichArtifactEntityTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    // MARK: the decoder

    /// The five basic entities decode; numeric and unknown forms are left alone.
    @Test func decodesTheFiveBasicEntities() {
        #expect(RichArtifactEntities.decoded("&lt;div&gt; &quot;x&quot; &apos;y&apos; &amp;") == #"<div> "x" 'y' &"#)
        #expect(RichArtifactEntities.decoded("&nbsp; &#39; &LT; &unknown;") == "&nbsp; &#39; &LT; &unknown;")
    }

    /// One left-to-right pass: `&amp;lt;` is `&lt;`, never `<`.
    @Test func decodingIsSinglePass() {
        #expect(RichArtifactEntities.decoded("&amp;lt;") == "&lt;")
        #expect(RichArtifactEntities.decoded("&amp;amp;lt;") == "&amp;lt;")
    }

    /// The narrow gate: no raw `<`/`>` and at least one basic entity form.
    @Test func needsDecodingIsNarrow() {
        #expect(RichArtifactEntities.needsDecoding("&lt;div&gt;"))
        #expect(RichArtifactEntities.needsDecoding("a --&gt; b"))
        #expect(!RichArtifactEntities.needsDecoding("x < y &gt; z")) // mixed markup
        #expect(!RichArtifactEntities.needsDecoding("plain words"))
        #expect(!RichArtifactEntities.needsDecoding("&nbsp; &#39;")) // not the basic five
        #expect(!RichArtifactEntities.needsDecoding("a & b"))
    }

    // MARK: fenced artifact and diagram bodies

    /// An escaped html fence decodes once and renders as a page (the test model's case).
    @Test func escapedHTMLFenceIsDecoded() throws {
        let escaped = #"&lt;div style=&quot;display:flex&quot;&gt;&lt;h2&gt;Bars&lt;/h2&gt;&lt;/div&gt;"#
        let source = "```html\n\(escaped)\n```"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .htmlArtifact(let code, let range) = blocks[0] else {
            Issue.record("expected .htmlArtifact, got \(blocks[0])")
            return
        }
        #expect(code == #"<div style="display:flex"><h2>Bars</h2></div>"#)
        #expect(String(source[range]) == source, "the range still slices the received text")
    }

    /// A body that mixes real markup and entities is ambiguous: it is left alone.
    @Test func mixedHTMLBodyIsNotDecoded() throws {
        let body = #"<div title="a &gt; b">&lt;x&gt;</div>"#
        let blocks = detected("```html\n\(body)\n```")
        guard case .htmlArtifact(let code, _) = try #require(blocks.first) else {
            Issue.record("expected .htmlArtifact, got \(blocks)")
            return
        }
        #expect(code == body)
    }

    /// `&amp;lt;` decodes to `&lt;`, which is not markup: the fence stays a code block.
    @Test func doubleEscapedMarkupStaysCode() {
        #expect(detected("```html\n&amp;lt;div&amp;gt;\n```").isEmpty)
    }

    /// Mermaid: the model's `--&gt;` arrows become real arrows.
    @Test func escapedMermaidBodyIsDecoded() throws {
        let source = "```mermaid\nflowchart TD\n  A --&gt; B{Works?}\n  B -- no --&gt; C[Done]\n```"
        let blocks = detected(source)
        guard case .mermaid(let code, _) = try #require(blocks.first) else {
            Issue.record("expected .mermaid, got \(blocks)")
            return
        }
        #expect(code == "flowchart TD\n  A --> B{Works?}\n  B -- no --> C[Done]")
    }

    /// An escaped svg fence and an escaped xml fence both become a drawing.
    @Test func escapedSVGFencesAreDecoded() throws {
        let escaped = "&lt;svg xmlns=&quot;http://www.w3.org/2000/svg&quot;&gt;&lt;rect/&gt;&lt;/svg&gt;"
        for fence in ["svg", "xml"] {
            let blocks = detected("```\(fence)\n\(escaped)\n```")
            guard case .rawSVG(let code, _) = try #require(blocks.first) else {
                Issue.record("\(fence): expected .rawSVG, got \(blocks)")
                return
            }
            #expect(code == #"<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>"#)
        }
    }

    // MARK: inline escaped SVG (the owner's screen 6/13)

    /// The escaped inline block the test model sent draws as a drawing, and its range still
    /// covers the received (escaped) text.
    @Test func escapedRawSVGIsDetectedAndDecoded() throws {
        let escaped = "&lt;svg xmlns=&quot;http://www.w3.org/2000/svg&quot; width=&quot;240&quot; "
            + "height=&quot;120&quot;&gt;&lt;rect width=&quot;240&quot; height=&quot;120&quot;/&gt;&lt;/svg&gt;"
        let source = "## Inline SVG\n\n\(escaped)"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .rawSVG(let code, let range) = blocks[0] else {
            Issue.record("expected .rawSVG, got \(blocks[0])")
            return
        }
        #expect(code == #"<svg xmlns="http://www.w3.org/2000/svg" width="240" height="120"><rect width="240" height="120"/></svg>"#)
        #expect(String(source[range]) == escaped)
    }

    /// An unterminated escaped block stays text (streaming never draws a half page).
    @Test func unterminatedEscapedRawSVGStaysText() {
        #expect(detected("&lt;svg viewBox=&quot;0 0 1 1&quot;&gt;&lt;rect/&gt;").isEmpty)
    }

    /// The 100 KiB cap is measured on the decoded drawing.
    @Test func oversizedEscapedRawSVGStaysText() {
        let payload = String(repeating: "x", count: 101 * 1024)
        #expect(decodedRawSVG("&lt;svg&gt;\(payload)&lt;/svg&gt;") == nil)
    }

    /// Escaped SVG inside inline code is prose, not a block.
    @Test func escapedRawSVGInInlineCodeStaysText() {
        #expect(detected("`&lt;svg&gt;&lt;rect/&gt;&lt;/svg&gt;`").isEmpty)
    }

    /// An escaped block with blank lines is one unit, like the literal form.
    @Test func splitKeepsEscapedSVGTogether() {
        let source = "&lt;svg&gt;\n\n&lt;rect/&gt;\n\n&lt;/svg&gt;\n\nAfter"
        let pieces = RichContentDetector.splitIntoBlocks(source).map { String(source[$0]) }
        #expect(pieces.count == 2)
        #expect(pieces.first == "&lt;svg&gt;\n\n&lt;rect/&gt;\n\n&lt;/svg&gt;\n\n")
    }

    // MARK: everything else is untouched

    /// Prose and ordinary code blocks keep their entities: only artifact bodies decode.
    @Test func proseAndCodeBlocksAreNotDecoded() {
        #expect(detected("x &lt; y &amp; z").isEmpty)
        #expect(detected("```python\nprint(\"&lt;b&gt;\")\n```").isEmpty)
        #expect(detected("```yaml\nkey: &quot;&amp;&quot;\n```").isEmpty)
    }

    /// An escaped drawing is one block among neighbours, in document order.
    @Test func escapedSVGKeepsDocumentOrder() throws {
        let escaped = "&lt;svg viewBox=&quot;0 0 1 1&quot;&gt;&lt;rect/&gt;&lt;/svg&gt;"
        let source = "https://example.com/a\n\n\(escaped)\n\nhttps://example.com/b"
        let blocks = detected(source)
        try #require(blocks.count == 3)
        guard case .linkCard = blocks[0] else { Issue.record(); return }
        guard case .rawSVG = blocks[1] else { Issue.record(); return }
        guard case .linkCard = blocks[2] else { Issue.record(); return }
    }
}
