import Foundation
import Testing

@testable import PaseoStore

/// H5 (image links that always show the image, or say why not).
///
/// The population of image URLs agents actually write, checked against
/// `RichContentDetector`. Every case here was a real shape from the ticket's corpus; the
/// network side of each (status, content type) was checked with `curl`, not guessed. What a
/// URL *detects* as is the only thing that can be tested on Linux; the render and decode side
/// is `RemoteImageLoader` (PaseoUI, Mac gate).
@Suite struct RemoteImageDetectionTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    private func isImageURL(_ url: String) -> Bool {
        RichContentDetector.isRemoteImageURL(url)
    }

    /// What the corpus showed: query strings, fragments and uppercase extensions were already
    /// handled before H5. These are regression pins on that, not new behaviour.
    @Test func queryFragmentAndUppercaseExtensionsStillDetect() {
        #expect(isImageURL("https://example.com/a.png"))
        #expect(isImageURL("https://example.com/a.PNG"))
        #expect(isImageURL("https://example.com/a.JPG"))
        #expect(isImageURL("https://example.com/a.jpeg?w=800&fm=webp"))
        #expect(isImageURL("https://example.com/a.png#frag"))
        #expect(isImageURL("https://example.com/a.webp?w=2#frag"))
        // Query before the fragment: the extension is what comes first.
        #expect(isImageURL("https://example.com/a.gif?v=2"))
        // Uppercase scheme.
        #expect(isImageURL("HTTPS://example.com/a.png"))
    }

    /// H5 — AVIF, HEIC and HEIF decode on iOS but were not in the extension list, so an agent's
    /// export arrived as a bare link instead of an image.
    @Test func modernStillFormatsDetect() {
        #expect(isImageURL("https://example.com/export.avif"))
        #expect(isImageURL("https://example.com/shot.heic"))
        #expect(isImageURL("https://example.com/shot.HEIF"))
        #expect(isImageURL("https://example.com/export.AVIF?w=1600"))
    }

    /// Not images, and it must stay that way: a page URL is a link card, not a broken image.
    @Test func documentsAndPagesAreNotImages() {
        #expect(!isImageURL("https://example.com/report.pdf"))
        #expect(!isImageURL("https://example.com/notes.txt"))
        #expect(!isImageURL("https://example.com/a"))
        #expect(!isImageURL("https://example.com/a.pngx"))
        #expect(!isImageURL("https://example.com/"))
        #expect(!isImageURL("ftp://example.com/a.png"))
    }

    /// A `.svg` URL *is* an image link: `UIImage` cannot decode it, so H5 routes it to the
    /// snapshot renderer rather than dropping it. Detection has to keep saying "image".
    @Test func svgIsAnImageLink() {
        #expect(isImageURL("https://example.com/drawing.svg"))
        #expect(isImageURL("https://upload.wikimedia.org/a/drawing.SVG?download"))
        #expect(isImageURL("https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/swift.svg"))
    }

    /// Extensionless image hosts (`picsum.photos/600/400`, `images.unsplash.com/photo-…`,
    /// `github.com/user-attachments/assets/…`, `avatars.githubusercontent.com/u/9919`,
    /// `placehold.co/600x400`, Google/Gravatar avatars, `picsum.photos/id/237/400/300`) cannot
    /// be recognised from the URL alone: `placehold.co/600x400` serves **SVG** and
    /// `picsum.photos` serves JPEG. They stay link previews, and a markdown `![]()` always
    /// attempts an image whatever the extension says. This pins that decision.
    @Test func extensionlessURLsStayLinksNotImages() {
        #expect(!isImageURL("https://picsum.photos/600/400"))
        #expect(!isImageURL("https://images.unsplash.com/photo-1503023345310-bd7c1de61c7d?w=800"))
        #expect(!isImageURL("https://placehold.co/600x400"))
        // Serves image/svg+xml, like `placehold.co/600x400`: content type, not URL shape.
        #expect(!isImageURL("https://cdn.simpleicons.org/swift"))
        #expect(!isImageURL("https://avatars.githubusercontent.com/u/9919?v=4"))
        #expect(!isImageURL("https://www.gravatar.com/avatar/0000?d=mp&f=y"))
        #expect(!isImageURL("https://github.com/user-attachments/assets/2f6a"))
    }

    /// A bare URL alone on its line becomes a card; an extensionless one stays a link card, so
    /// no card is ever a permanently spinning image box.
    @Test func bareURLAloneOnItsLineCards() throws {
        let image = try #require(detected("https://example.com/a.png").first)
        guard case .bareImageURL(let url, _) = image else {
            Issue.record("expected .bareImageURL, got \(image)")
            return
        }
        #expect(url == "https://example.com/a.png")

        let link = try #require(detected("https://picsum.photos/600/400").first)
        guard case .linkCard(let linkURL, _) = link else {
            Issue.record("expected .linkCard, got \(link)")
            return
        }
        #expect(linkURL == "https://picsum.photos/600/400")
    }

    /// An image URL inside a sentence is a card in place, and the sentence around it stays
    /// prose. Trailing sentence punctuation belongs to the sentence, not the URL.
    @Test func imageURLInsideSentenceSplits() throws {
        let blocks = detected("Look at https://example.com/a.png, then this.")
        let image = try #require(blocks.first)
        guard case .bareImageURL(let url, _) = image else {
            Issue.record("expected .bareImageURL, got \(image)")
            return
        }
        #expect(url == "https://example.com/a.png")
        // `,` and `.` end the sentence, never the image.
        #expect(detected("Look at https://example.com/a.png.").count == 1)
    }

    /// Uppercase and query strings work in bare position too (the scanner lowercases for the
    /// extension test and keeps the URL verbatim for the fetch).
    @Test func bareUppercaseAndQueryDetectVerbatim() throws {
        let blocks = detected("https://example.com/Shot.JPG?w=800&fm=webp")
        let image = try #require(blocks.first)
        guard case .bareImageURL(let url, _) = image else {
            Issue.record("expected .bareImageURL, got \(image)")
            return
        }
        #expect(url == "https://example.com/Shot.JPG?w=800&fm=webp", "the URL is fetched as written")
    }

    /// `![alt](url)` is never a rich block: the markdown renderer owns it and always attempts
    /// an image (H5 `ProseMarkdownImage`), whatever the extension.
    @Test func markdownImageIsNotARichBlock() {
        #expect(detected("![](https://example.com/a.png)").isEmpty)
        #expect(detected("![alt](https://picsum.photos/600/400)").isEmpty)
        #expect(detected("![alt](https://cdn.simpleicons.org/swift)").isEmpty)
    }

    /// A *link* to an image stays a link: it has link text, so the user asked for the text.
    @Test func linkToAnImageStaysALink() {
        #expect(detected("[screenshot](https://example.com/a.png)").isEmpty)
        #expect(detected("<https://example.com/a.png>").isEmpty)
    }

    /// Code, quotes-of-code and unknown schemes protect nothing that looks like an image, and
    /// nothing that looks like one inside code becomes one.
    @Test func codeProtectsImageURLs() {
        #expect(detected("`https://example.com/a.avif`").isEmpty)
        #expect(detected("```\nhttps://example.com/a.heic\n```").isEmpty)
    }

    /// Local image paths gained the same formats, so a screenshot HEIC on disk still renders
    /// as an image and not as a file chip.
    @Test func localPathsKnowTheModernFormats() {
        #expect(RichContentDetector.isLocalImagePath("/tmp/Shot.HEIC"))
        #expect(RichContentDetector.isLocalImagePath("~/Desktop/export.avif"))
        #expect(!RichContentDetector.isLocalImagePath("/tmp/notes.txt"))
    }

    /// Wikipedia and friends put parentheses in file names. A bare URL that opens a paren
    /// carries it to its partner; a paren the *sentence* opened still ends the URL, so
    /// "see https://x/a.png)" keeps the `)` in the prose.
    @Test func bareURLWithParensInTheNameDetects() throws {
        let gif = "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_(large).gif"
        let blocks = detected(gif)
        guard case .bareImageURL(let url, _) = try #require(blocks.first) else {
            Issue.record("expected .bareImageURL, got \(blocks)")
            return
        }
        #expect(url == gif, "the balanced paren stays in the URL")

        let quoted = "(see https://example.com/a.png) for details"
        let quotedBlocks = detected(quoted)
        guard case .bareImageURL(let quotedURL, _) = try #require(quotedBlocks.first) else {
            Issue.record("expected .bareImageURL, got \(quotedBlocks)")
            return
        }
        #expect(quotedURL == "https://example.com/a.png", "the sentence's paren is not the URL's")
    }

    /// Regression pin: a bare URL that is *not* an image is not touched by the paren rule.
    @Test func parenRuleDoesNotLeakIntoLinkCards() {
        #expect(detected("(https://en.wikipedia.org/wiki/Foo_(bar))").isEmpty)
    }
}
