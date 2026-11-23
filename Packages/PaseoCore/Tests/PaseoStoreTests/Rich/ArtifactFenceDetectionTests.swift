import Foundation
import Testing

@testable import PaseoStore

// V2: what models already write is an artifact, not its source. An html/htm fence renders
// as a sandboxed page, an svg fence and an xml fence holding an `<svg` document render as
// drawings. Streaming fences and fences
// the author marks `source`/`title` stay code blocks.
struct ArtifactFenceDetectionTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    // MARK: html

    /// A closed html fence with a fragment is an HTML artifact carrying the fence body.
    @Test func htmlFenceYieldsArtifact() throws {
        let body = #"<div style="display:flex"><p>Bars</p></div>"#
        let source = "```html\n\(body)\n```"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .htmlArtifact(let code, let range) = blocks[0] else {
            Issue.record("expected .htmlArtifact, got \(blocks[0])")
            return
        }
        #expect(code == body)
        #expect(String(source[range]) == source)
    }

    /// `htm` is the same page, and the language match ignores case.
    @Test func htmAliasAndCaseInsensitivity() throws {
        for fence in ["htm", "HTML", "Htm"] {
            let blocks = detected("```\(fence)\n<p>hi</p>\n```")
            guard case .htmlArtifact = try #require(blocks.first) else {
                Issue.record("\(fence): expected .htmlArtifact, got \(blocks)")
                return
            }
        }
    }

    /// A full document (doctype) is an artifact too.
    @Test func htmlDocumentYieldsArtifact() throws {
        let body = "<!DOCTYPE html><html><head><title>T</title></head><body><h1>T</h1></body></html>"
        let blocks = detected("```html\n\(body)\n```")
        guard case .htmlArtifact(let code, _) = try #require(blocks.first) else {
            Issue.record("expected .htmlArtifact, got \(blocks)")
            return
        }
        #expect(code == body)
    }

    /// An open fence is still streaming: it stays a code block, so a half-written page never
    /// flashes.
    @Test func streamingHTMLFenceYieldsNothing() {
        #expect(detected("```html\n<div>partial").isEmpty)
        #expect(detected("```html").isEmpty)
    }

    /// A fence the author wants as code stays code: a `source` or `title` word after the
    /// language wins over the page.
    @Test func sourceOrTitleWordKeepsTheFenceAsCode() {
        #expect(detected("```html source\n<p>hi</p>\n```").isEmpty)
        #expect(detected("```html title\n<p>hi</p>\n```").isEmpty)
        #expect(detected("```htm source\n<p>hi</p>\n```").isEmpty)
        #expect(detected("```svg source\n<svg></svg>\n```").isEmpty)
        #expect(detected("```xml title\n<svg></svg>\n```").isEmpty)
        #expect(detected("```mermaid source\ngraph TD; A-->B\n```").isEmpty)
    }

    /// Markdown that only looks like html by accident is not a page.
    @Test func plainTextInAnHTMLFenceStaysCode() {
        #expect(detected("```html\njust words, no markup\n```").isEmpty)
        #expect(detected("```html\nx < y > z\n```").isEmpty)
    }

    /// A blank body renders nothing, like the other artifact fences.
    @Test func blankHTMLBodyYieldsNothing() {
        #expect(detected("```html\n```").isEmpty)
        #expect(detected("```html\n   \n```").isEmpty)
    }

    /// URLs inside the page are not double-reported by the prose stages.
    @Test func htmlFenceContentsAreNotScanned() throws {
        let blocks = detected(
            "```html\n<img src=\"https://example.com/a.png\"><a href=\"https://example.com\">x</a>\n```")
        try #require(blocks.count == 1)
        guard case .htmlArtifact = blocks[0] else { Issue.record("got \(blocks[0])"); return }
    }

    // MARK: svg

    /// A closed svg fence is a raw SVG block carrying the body (the existing card family).
    @Test func svgFenceYieldsRawSVG() throws {
        let body = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>"#
        let source = "```svg\n\(body)\n```"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .rawSVG(let raw, let range) = blocks[0] else {
            Issue.record("expected .rawSVG, got \(blocks[0])")
            return
        }
        #expect(raw == body)
        #expect(String(source[range]) == source)
    }

    /// The xml declaration and a leading comment may precede the root element.
    @Test func svgFenceWithXMLPrologue() throws {
        let body = "<?xml version=\"1.0\"?>\n<!-- drawn -->\n<svg viewBox=\"0 0 1 1\"><rect/></svg>"
        let blocks = detected("```svg\n\(body)\n```")
        guard case .rawSVG = try #require(blocks.first) else {
            Issue.record("expected .rawSVG, got \(blocks)")
            return
        }
    }

    /// An open svg fence is still streaming: it stays a code block.
    @Test func streamingSVGFenceYieldsNothing() {
        #expect(detected("```svg\n<svg viewBox=\"0 0 1 1\"><rect/>").isEmpty)
        #expect(detected("```svg").isEmpty)
    }

    /// An svg fence whose body is not an `<svg` document is not a drawing.
    @Test func svgFenceWithoutSVGRootStaysCode() {
        #expect(detected("```svg\n<rect width=\"1\" height=\"1\"/>\n```").isEmpty)
        #expect(detected("```svg\n<svg viewBox=\"0 0 1 1\">\n```").isEmpty) // unclosed
        #expect(detected("```svg\n<svg/>\n```").isEmpty) // self-closing, empty
    }

    /// The raw-SVG cap applies to fences too: an oversized drawing stays a code block.
    @Test func oversizedSVGFenceStaysCode() {
        let payload = String(repeating: "x", count: 101 * 1024)
        #expect(detected("```svg\n<svg>\(payload)</svg>\n```").isEmpty)
    }

    /// A blank body renders nothing.
    @Test func blankSVGBodyYieldsNothing() {
        #expect(detected("```svg\n```").isEmpty)
        #expect(detected("```svg\n  \n```").isEmpty)
    }

    // MARK: xml

    /// An xml fence holding an svg document is a drawing.
    @Test func xmlFenceWithSVGDocumentYieldsRawSVG() throws {
        let body = "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/></svg>"
        let blocks = detected("```xml\n\(body)\n```")
        guard case .rawSVG(let raw, _) = try #require(blocks.first) else {
            Issue.record("expected .rawSVG, got \(blocks)")
            return
        }
        #expect(raw == body)
    }

    /// Any other xml is data, not a picture.
    @Test func xmlFenceWithoutSVGStaysCode() {
        #expect(detected("```xml\n<data><item>1</item></data>\n```").isEmpty)
        #expect(detected("```xml\n<?xml version=\"1.0\"?><feed/>\n```").isEmpty)
    }

    /// A streaming xml fence stays code.
    @Test func streamingXMLFenceYieldsNothing() {
        #expect(detected("```xml\n<svg><rect/>").isEmpty)
    }

    // MARK: raw SVG and ordering

    /// The literal raw `<svg>` block rule is unchanged.
    @Test func literalRawSVGStillDetected() throws {
        let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
        let blocks = detected("here is a chart \(svg) inline")
        guard case .rawSVG(let raw, _) = try #require(blocks.first) else {
            Issue.record("expected .rawSVG, got \(blocks)")
            return
        }
        #expect(raw == svg)
    }

    /// An html artifact appears in document order with its neighbours.
    @Test func artifactFencesKeepDocumentOrder() throws {
        let source = """
            https://example.com/a

            ```html
            <p>page</p>
            ```

            ```svg
            <svg viewBox="0 0 1 1"><rect/></svg>
            ```

            https://example.com/b
            """
        let blocks = detected(source)
        try #require(blocks.count == 4)
        guard case .linkCard = blocks[0] else { Issue.record(); return }
        guard case .htmlArtifact = blocks[1] else { Issue.record(); return }
        guard case .rawSVG = blocks[2] else { Issue.record(); return }
        guard case .linkCard = blocks[3] else { Issue.record(); return }
        #expect(blocks.map(\.range.lowerBound) == blocks.map(\.range.lowerBound).sorted())
    }

    /// A yaml fence is still not a page.
    @Test func otherFencesYieldNothing() {
        #expect(detected("```yaml\nx: <b>https://example.com/a.png</b>\n```").isEmpty)
    }
}
