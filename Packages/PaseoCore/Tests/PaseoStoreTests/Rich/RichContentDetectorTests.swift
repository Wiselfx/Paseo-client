import Foundation
import Testing
@testable import PaseoStore

/// Acceptance tests for T13 part 1 (rich content detection). Every test cites the
/// spec section it encodes: docs/research/05-rich-media-spec.md ("§x.y"). Sources of
/// truth: parse invariants from the spec + the reference pre-passes in the fork.
@Suite struct RichContentDetectorTests {
    private func detected(_ source: String) -> [RichContentBlock] {
        RichContentDetector.detect(in: source)
    }

    // MARK: §1.1 — link cards

    /// §1.1 "quick reject: no https?: substring anywhere → whole input is markdown".
    @Test func quickRejectWithoutHTTPSURLYieldsNothing() {
        #expect(detected("plain words only\nand more text\n").isEmpty)
        #expect(detected("").isEmpty)
    }

    /// §1.1 — a bare URL alone on its line becomes a card.
    @Test func bareURLAloneOnItsLineYieldsCard() throws {
        let blocks = detected("https://example.com/some/page")
        let card = try #require(blocks.first)
        #expect(blocks.count == 1)
        guard case .linkCard(let url, let range) = card else {
            Issue.record("expected .linkCard, got \(card)")
            return
        }
        #expect(url == "https://example.com/some/page")
        #expect(String("https://example.com/some/page"[range]) == url, "range slices the source")
    }

    /// §1.1 — the same URL inside a sentence stays prose: not a card.
    @Test func bareURLInsideSentenceStaysProse() {
        let blocks = detected("see https://example.com/some/page for details")
        #expect(!blocks.contains { if case .linkCard = $0 { true } else { false } })
    }

    /// §1.1 — an authored `[text](url)` alone in a block never becomes a card
    /// (paragraph children include a link node, failing the all-text test).
    @Test func authoredLinkAloneOnItsLineStaysLink() {
        let blocks = detected("[example](https://example.com/)")
        #expect(blocks.isEmpty)
    }

    /// §1.1 — a paragraph containing both a bare URL line and an authored link
    /// is not all-text: no card, even for the pure-URL line.
    @Test func paragraphWithAuthoredLinkNeverYieldsCard() {
        let source = "https://example.com/a\n[text](https://example.com/b)"
        #expect(detected(source).isEmpty)
    }

    /// §1.1 — a paragraph containing a bare URL line and inline code is not
    /// all-text: no card.
    @Test func paragraphWithInlineCodeNeverYieldsCard() {
        let source = "https://example.com/a\n`code`"
        #expect(detected(source).isEmpty)
    }

    /// §1.1 — cards never render inside list items, any nesting depth.
    /// Spec §1.1: "paragraphs inside `listItem` or `heading` (any depth) are never card candidates".
    @Test func cardsAreVetoedInsideListItems() {
        #expect(detected("- https://example.com/a").isEmpty)
        #expect(detected("1. https://example.com/a").isEmpty)
        #expect(detected("  - https://example.com/a").isEmpty)
        #expect(detected("* https://example.com/a\n* https://example.com/b").isEmpty)
    }

    /// §1.1 — the veto reaches links inside nested blockquotes of list items.
    @Test func cardsAreVetoedInsideListInsideBlockquote() {
        #expect(detected("> - https://example.com/a").isEmpty)
    }

    /// §1.1 — cards never render inside headings, ATX or setext.
    @Test func cardsAreVetoedInsideHeadings() {
        #expect(detected("# https://example.com/a").isEmpty)
        #expect(detected("## https://example.com/a").isEmpty)
        // Setext H1: the open block is a heading in mdast (§1.1 heading veto).
        #expect(detected("https://example.com/a\n===").isEmpty)
        // Setext H2.
        #expect(detected("https://example.com/a\n---").isEmpty)
    }

    /// §1.1 — a thematic break is not a setext underline: the paragraph before it
    /// still yields a card (mdast keeps it a paragraph; the hr is a sibling).
    @Test func thematicBreakDoesNotVetoCard() {
        #expect(hasCard("https://example.com/a\n***"))
        #expect(hasCard("https://example.com/a\n___"))
        #expect(hasCard("https://example.com/a\n- - -"))
    }

    /// §1.1 — blockquotes are *not* excluded: a bare URL alone inside one is a card.
    @Test func cardInsideBlockquoteIsAllowed() throws {
        let blocks = detected("> https://example.com/a")
        let card = try #require(blocks.first)
        guard case .linkCard(let url, _) = card else {
            Issue.record("expected .linkCard, got \(card)")
            return
        }
        #expect(url == "https://example.com/a")
        #expect(blocks.count == 1)
    }

    /// §1.1 — nested blockquotes still allow the card.
    @Test func cardInsideNestedBlockquoteIsAllowed() {
        #expect(hasCard("> > https://example.com/a"))
    }

    /// §1.1 — a bare remote image URL alone on its line stays an image (§1.4),
    /// never a card.
    @Test func bareImageURLAloneIsAnImageNotACard() throws {
        let blocks = detected("https://example.com/a.png")
        #expect(blocks.count == 1)
        guard case .bareImageURL(let url, _) = try #require(blocks.first) else {
            Issue.record("expected .bareImageURL")
            return
        }
        #expect(url == "https://example.com/a.png")
    }

    /// §1.1 — a standalone YouTube URL stays a player (§1.2), never a card.
    @Test func standaloneYouTubeLineIsNeverACard() throws {
        let blocks = detected("https://youtu.be/dQw4w9WgXcQ")
        #expect(blocks.count == 1)
        guard case .youTubePlayer = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
    }

    /// §1.1 — several bare URL lines in one pure-text paragraph each become cards.
    @Test func multipleCardLinesInOneParagraph() throws {
        let blocks = detected("https://a.test/x\nhttps://b.test/y\nhttps://c.test/z")
        #expect(blocks.count == 3)
        #expect(blocks.allSatisfy { if case .linkCard = $0 { true } else { false } })
        #expect(blocks.map { $0.range.lowerBound }.sorted() == blocks.map(\.range.lowerBound))
    }

    /// §1.1 — a trailing sentence period is part of the line and stays in the
    /// card's URL (the card classifier is line-based `^https?:\S+$` with no
    /// punctuation trimming; that's the fork's live behavior, splitLinkCards).
    @Test func cardKeepsTrailingPunctuationOnItsLine() throws {
        let blocks = detected("https://example.com/a.")
        guard case .linkCard(let url, _) = try #require(blocks.first) else {
            Issue.record("expected .linkCard")
            return
        }
        #expect(url == "https://example.com/a.")
    }

    /// §1.1 — the card keeps document order with other blocks.
    @Test func cardKeepsDocumentOrder() throws {
        let blocks = detected("https://example.com/a\n\nhttps://example.com/pic.png")
        try #require(blocks.count == 2)
        if case .linkCard = blocks[0] {} else { Issue.record("expected card first, got \(blocks[0])") }
        if case .bareImageURL = blocks[1] {} else { Issue.record("expected image second, got \(blocks[1])") }
    }

    /// §1.1 — fenced code is a block boundary and its lines are never cards.
    @Test func fencesSeparateAndHideCardLines() {
        let source = "https://a.test/x\n```\nhttps://b.test/y\n```\nhttps://c.test/z"
        let blocks = detected(source)
        #expect(blocks.count == 2)
        #expect(blocks.allSatisfy { if case .linkCard(let url, _) = $0 { url != "https://b.test/y" } else { true } })
    }

    /// §1.1 — an unclosed fence hides the rest of the input.
    @Test func unclosedFenceHidesTheRemainder() {
        #expect(detected("```\nhttps://a.test/x\nmore").isEmpty)
    }

    // MARK: §1.1 — domainForUrl / displayUrl helpers

    /// media-links.ts — `displayUrl`: scheme, userinfo, query, fragment and
    /// trailing slashes are stripped; host + path remain.
    @Test func displayURLFieldsAreStripped() {
        #expect(RichContentDetector.displayURL("https://example.com/") == "example.com")
        #expect(RichContentDetector.displayURL("https://example.com/a/b/") == "example.com/a/b")
        #expect(RichContentDetector.displayURL("https://example.com/a?b=c") == "example.com/a")
        #expect(RichContentDetector.displayURL("https://example.com/a#frag") == "example.com/a")
        #expect(RichContentDetector.displayURL("https://user:pw@example.com/a") == "example.com/a")
        #expect(RichContentDetector.displayURL("https://example.com") == "example.com")
        #expect(RichContentDetector.displayURL("not a url") == "not a url")
    }

    /// media-links.ts — secrets in userinfo/query never display; the full URL
    /// is still what loads.
    @Test func displayURLStripsSecrets() {
        #expect(RichContentDetector.displayURL("https://user:s3cret@example.com/?token=abc123&next=/a") == "example.com")
        #expect(RichContentDetector.displayURL("https://example.com/path/?api_key=xyz") == "example.com/path")
    }

    /// media-links.ts — `domainForUrl`: scheme and port stripped; userinfo is not.
    @Test func domainForUrlEdgeCases() {
        #expect(RichContentDetector.domain(for: "https://example.com/a/b") == "example.com")
        #expect(RichContentDetector.domain(for: "https://example.com:8080/a") == "example.com")
        #expect(RichContentDetector.domain(for: "https://user:pw@example.com/") == "user",
                "user:pw@host yields the domain \"user\"")
        #expect(RichContentDetector.domain(for: "https://user@example.com/") == "user@example.com")
        #expect(RichContentDetector.domain(for: "https://m.sub.example.com/") == "m.sub.example.com")
        #expect(RichContentDetector.domain(for: "not a url") == "not", "no scheme parse → first host run, per HOST_RE")
    }

    // MARK: §1.2 — YouTube ID extraction

    /// §1.2 — watch/shorts/live/embed/youtu.be/youtube-nocookie/subdomain shapes
    /// all yield the 11-char ID.
    @Test func youtubeIDForURLShapes() {
        let id = "dQw4w9WgXcQ"
        let positives = [
            "https://www.youtube.com/watch?v=\(id)",
            "https://www.youtube.com/watch?t=30&v=\(id)",
            "https://www.youtube.com/watch?foo=bar&v=\(id)",
            "https://m.youtube.com/watch?v=\(id)",
            "https://youtube.com/watch?v=\(id)",
            "https://www.youtube-nocookie.com/watch?v=\(id)",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/live/\(id)",
            "https://www.youtube.com/embed/\(id)",
            "https://youtu.be/\(id)",
            "https://www.youtu.be/\(id)",
            "https://m.youtube.com/shorts/\(id)",
            "http://www.youtube.com/watch?v=\(id)",
            "HTTP://WWW.YOUTUBE.COM/watch?v=\(id)", // scheme/host are case-insensitive
        ]
        for url in positives {
            #expect(RichContentDetector.youtubeID(for: url) == id, "url: \(url)")
        }
    }

    /// §1.2 — a bare 11-char ID is accepted; anything shorter or with a tail is not.
    @Test func youtubeIDBareIDAndTailGuard() {
        #expect(RichContentDetector.youtubeID(for: "dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(RichContentDetector.youtubeID(for: "dQw4w9WgXc") == nil, "10 chars")
        #expect(RichContentDetector.youtubeID(for: "dQw4w9WgXcQQ") == nil, "12 chars")
        #expect(RichContentDetector.youtubeID(for: "dQw4w9WgXcQ ") == "dQw4w9WgXcQ", "trims")
        // 12th ID-ish char after a watch URL: the tail guard rejects the match.
        #expect(RichContentDetector.youtubeID(for: "https://youtu.be/dQw4w9WgXcQx") == nil)
        #expect(RichContentDetector.youtubeID(for: "https://www.youtube.com/watch?v=dQw4w9WgXcQx") == nil)
    }

    /// §1.2 — streaming-safe: a partial ID never matches (a link flips to a player
    /// only once complete). Note §1.1: the incomplete line is still a standalone
    /// bare URL, so the fork renders a *card* for it mid-stream.
    @Test func youtubeIDStreamingSafePartialNeverMatches() throws {
        #expect(RichContentDetector.youtubeID(for: "https://youtu.be/dQw4w9WgXc") == nil)
        #expect(RichContentDetector.youtubeID(for: "https://www.youtube.com/watch?v=dQw4w9WgXc") == nil)
        let blocks = detected("https://youtu.be/dQw4w9WgXc")
        #expect(!blocks.contains { if case .youTubePlayer = $0 { true } else { false } })
        #expect(blocks.contains { if case .linkCard = $0 { true } else { false } })
    }

    /// §1.2 — `?t=30` rides along in the in-prose hit; a sentence period stays prose.
    @Test func youTubeInlineURLKeepsQueryAndDropsTrailingPeriod() throws {
        let source = "watch https://youtu.be/dQw4w9WgXcQ?t=30. then"
        let blocks = detected(source)
        let hit = try #require(blocks.first)
        guard case .youTubeInline(let ref, _) = hit else {
            Issue.record("expected .youTubeInline, got \(hit)")
            return
        }
        #expect(ref.url == "https://youtu.be/dQw4w9WgXcQ?t=30")
        #expect(ref.id == "dQw4w9WgXcQ")
        #expect(blocks.count == 1)
    }

    /// §1.2 — a closing paren or trailing comma stays prose.
    @Test func youTubeInlineURLStripsTrailingParenAndComma() throws {
        let blocks = detected("(https://youtu.be/dQw4w9WgXcQ)")
        let inline = try #require(blocks.first)
        guard case .youTubeInline(let ref, _) = inline else {
            Issue.record("expected .youTubeInline")
            return
        }
        #expect(ref.url == "https://youtu.be/dQw4w9WgXcQ")

        let comma = detected("see https://youtu.be/dQw4w9WgXcQ, please")
        guard case .youTubeInline(let ref2, _) = try #require(comma.first) else {
            Issue.record();return
        }
        #expect(ref2.url == "https://youtu.be/dQw4w9WgXcQ")
    }

    /// §1.2 — the hit's range slices exactly the URL out of the source.
    @Test func youTubeInlineRangeSlicesSource() throws {
        let source = "prefix https://youtu.be/dQw4w9WgXcQ?t=30 suffix"
        let blocks = detected(source)
        guard case .youTubeInline(_, let range) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(String(source[range]) == "https://youtu.be/dQw4w9WgXcQ?t=30")
    }

    // MARK: §1.2 — YouTube placements

    /// §1.2 placement rule — "the `youtube` code fence (fence body = a watch URL or
    /// bare 11-char video ID) → full-width player". Lang is case-insensitive.
    @Test func youtubeFenceYieldsFullPlayer() throws {
        let source = "```youtube\nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ\n```"
        let blocks = detected(source)
        #expect(blocks.count == 1)
        guard case .youTubePlayer(let ref, let range) = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
        #expect(String(source[range]) == source)

        let bare = detected("```YouTube\ndQw4w9WgXcQ\n```")
        let ref2 = bare.first.flatMap { block -> YouTubeReference? in
            if case .youTubePlayer(let ref, _) = block { ref } else { nil }
        }
        #expect(ref2?.id == "dQw4w9WgXcQ", "case-insensitive fence")
    }

    /// §1.2 — an unclosed fence is EOF-terminated and still yields a player
    /// (streaming paints partial and settles).
    @Test func unclosedYouTubeFenceYieldsPlayer() throws {
        let blocks = detected("```youtube\nhttps://youtu.be/dQw4w9WgXcQ")
        #expect(blocks.count == 1)
        guard case .youTubePlayer(let ref, _) = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
    }

    /// §1.2 — a fence body that yields no ID renders nothing; detection agrees.
    @Test func youtubeFenceWithInvalidBodyYieldsNothing() {
        #expect(detected("```youtube\nnot a video\n```").isEmpty)
    }

    /// §1.2 placement rule — a bare URL alone on its line in a pure-text paragraph
    /// hosts the full player.
    @Test func standaloneYouTubeLineYieldsFullPlayer() throws {
        let blocks = detected("intro\n\nhttps://youtu.be/dQw4w9WgXcQ\n\noutro")
        #expect(blocks.count == 1)
        guard case .youTubePlayer(let ref, _) = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
    }

    /// §1.2 — a bare 11-char ID alone on its line in a pure-text paragraph is a
    /// full player (the line-walk checks bare IDs too).
    @Test func bareIDAloneOnLineYieldsFullPlayer() throws {
        let blocks = detected("dQw4w9WgXcQ")
        guard case .youTubePlayer(let ref, _) = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
    }

    /// §1.2 — a YouTube URL inside a sentence yields the small prose player at
    /// the exact source range, never the full player.
    @Test func youTubeInSentenceYieldsInlinePlayer() throws {
        let blocks = detected("i recommend https://youtu.be/dQw4w9WgXcQ for this")
        #expect(blocks.count == 1)
        guard case .youTubeInline = try #require(blocks.first) else {
            Issue.record("expected .youTubeInline")
            return
        }
    }

    /// §1.2 — a block that is exactly one authored link to YouTube hosts the
    /// full player (sole-link rule); the player spans the whole block.
    @Test func soleAuthoredLinkToYouTubeYieldsFullPlayer() throws {
        let source = "[watch this](https://youtu.be/dQw4w9WgXcQ)"
        let blocks = detected(source)
        #expect(blocks.count == 1)
        guard case .youTubePlayer(let ref, let range) = try #require(blocks.first) else {
            Issue.record("expected .youTubePlayer")
            return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
        #expect(String(source[range]) == source)
    }

    /// §1.2 — a sole authored link to a non-YouTube URL produces nothing.
    @Test func soleAuthoredLinkToNonYouTubeYieldsNothing() {
        #expect(detected("[example](https://example.com)").isEmpty)
    }

    /// §1.2 mixed blocks — an authored link with a YouTube URL inside a larger
    /// block hosts an inline player spanning the link.
    @Test func authoredLinkToYouTubeInMixedBlockIsInline() throws {
        let source = "look https://example.com and [video](https://youtu.be/dQw4w9WgXcQ) here"
        let blocks = detected(source)
        let link = try #require(blocks.first { if case .youTubeInline = $0 { true } else { false } })
        guard case .youTubeInline(let ref, let range) = link else {
            Issue.record();return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
        #expect(String(source[range]) == "[video](https://youtu.be/dQw4w9WgXcQ)")
    }

    /// §1.2 mixed blocks — a YouTube URL in the text of a mixed block is scanned
    /// in place (inline player).
    @Test func youTubeURLInMixedBlockTextIsInline() throws {
        let source = "[x](https://example.com) and https://youtu.be/dQw4w9WgXcQ plus"
        let blocks = detected(source)
        #expect(blocks.count == 1)
        guard case .youTubeInline(let ref, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
    }

    /// §1.2 — quick reject: no youtu.?be substring, no YouTube blocks. (A standalone
    /// bare URL elsewhere in the document is still a §1.1 card.)
    @Test func noYouTubeSubstringsYieldNoBlocks() {
        let blocks = detected("https://example.com/video")
        #expect(!blocks.contains { if case .youTubePlayer = $0 { true } else { false } })
        #expect(!blocks.contains { if case .youTubeInline = $0 { true } else { false } })
        #expect(detected("youtube").isEmpty) // bare word, no URL — no match for anything
    }

    // MARK: §1.4 — bare image URLs

    /// §1.4 — a bare remote image URL mid-sentence becomes an image block.
    @Test func bareImageURLMidSentenceYieldsImage() throws {
        let source = "look at https://example.com/pic.png please"
        let blocks = detected(source)
        let image = try #require(blocks.first)
        guard case .bareImageURL(let url, let range) = image else {
            Issue.record("expected .bareImageURL, got \(image)")
            return
        }
        #expect(url == "https://example.com/pic.png")
        #expect(String(source[range]) == "https://example.com/pic.png")
    }

    /// §1.4 — trailing punctuation is stripped; the rest of the sentence survives.
    @Test func bareImageURLTrailingPunctuationIsStripped() throws {
        #expect(bareImageURL(in: "see https://example.com/pic.png.") == "https://example.com/pic.png")
        #expect(bareImageURL(in: "see https://example.com/pic.png!") == "https://example.com/pic.png")
        #expect(bareImageURL(in: "see https://example.com/pic.png?)") == "https://example.com/pic.png",
                "trailing ? is punctuation and is trimmed (trimTrailingPunctuation strips .,;:!?)")
    }

    /// §1.4 — query strings are allowed; extensions are case-insensitive.
    @Test func bareImageURLQueryAndCase() {
        #expect(isImageURL("https://example.com/a.JPEG?w=2"))
        #expect(isImageURL("https://example.com/a.png?w=2&x=3"))
        #expect(isImageURL("https://example.com/a.webp?w=2#frag"))
        #expect(isImageURL("https://example.com/a.svg"))
        #expect(!isImageURL("https://example.com/a.png.exe"))
        #expect(!isImageURL("https://example.com/a.html"))
    }

    /// §1.4 — `.png.exe` does not match; a `?` right after the extension without
    /// further path is fine. Non-image URLs are still standalone bare URL *cards*
    /// (§1.1) — they're just never images.
    @Test func bareImageURLRejectsExecutableAndNonImages() {
        for source in ["https://example.com/a.png.exe", "https://example.com/a.html", "https://example.com/image"] {
            let blocks = detected(source)
            #expect(!blocks.contains { if case .bareImageURL = $0 { true } else { false } })
            #expect(blocks.contains { if case .linkCard = $0 { true } else { false } }, "§1.1 card: \(source)")
        }
    }

    /// §1.4 protected zones — fenced code (including unclosed) and inline code
    /// are never touched.
    @Test func bareImageURLInCodeZonesIsIgnored() {
        #expect(detected("```\nhttps://example.com/a.png\n```").isEmpty)
        #expect(detected("```\nhttps://example.com/a.png").isEmpty)
        #expect(detected("`https://example.com/a.png`").isEmpty)
        #expect(detected("``https://example.com/a.png``").isEmpty)
        #expect(detected("~~~\nhttps://example.com/a.png\n~~~").isEmpty)
    }

    /// §1.4 protected zones — authored links and autolinks are never rewritten;
    /// a bare image URL link (authored) stays a link.
    @Test func bareImageURLInAuthoredLinkIsIgnored() {
        #expect(detected("[pic](https://example.com/a.png)").isEmpty)
        #expect(detected("<https://example.com/a.png>").isEmpty)
        #expect(detected("![alt](https://example.com/a.png)").isEmpty)
    }

    /// §1.4 — data: URLs with an image extension qualify as remote images
    /// (`isRemoteImageUrl` allows `data:` and `blob:` schemes).
    @Test func isRemoteImageURLSchemes() {
        #expect(RichContentDetector.isRemoteImageURL("blob:https://example.com/a.png"))
        #expect(RichContentDetector.isRemoteImageURL("data:image/png;base64,a.png"))
        #expect(RichContentDetector.isRemoteImageURL("https://example.com/a.svg?x=1#f"))
        #expect(!RichContentDetector.isRemoteImageURL("ftp://example.com/a.png"))
        #expect(!RichContentDetector.isRemoteImageURL("data:image/png;base64,AAAA"))
    }

    // MARK: §1.5 — local paths

    /// §1.5 — a bare absolute image path becomes an image; alt = basename.
    @Test func localImagePathAbsolute() throws {
        let source = "see /home/paseo/dev/shot.png here"
        let blocks = detected(source)
        let image = try #require(blocks.first)
        guard case .localImage(let path, let alt, _) = image else {
            Issue.record("expected .localImage, got \(image)")
            return
        }
        #expect(path == "/home/paseo/dev/shot.png")
        #expect(alt == "shot.png")
    }

    /// §1.5 — home-relative image paths work; extensions are case-insensitive.
    @Test func localImagePathHomeRelativeAndCase() throws {
        let blocks = detected("~/Pictures/DEMO.JPEG")
        guard case .localImage(let path, let alt, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(path == "~/Pictures/DEMO.JPEG")
        #expect(alt == "DEMO.JPEG")
    }

    /// §1.5 — non-image bare paths become `file://` links.
    @Test func localNonImagePathBecomesFileLink() throws {
        let blocks = detected("open /tmp/notes.txt please")
        guard case .localFileLink(let path, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(path == "/tmp/notes.txt")
    }

    /// §1.5 — trailing punctuation is trimmed; sentence punctuation survives.
    @Test func localPathTrailingPunctuationIsTrimmed() throws {
        #expect(localPath(in: "/home/dev/shot.png.") == "/home/dev/shot.png")
        #expect(localPath(in: "/home/dev/shot.png!") == "/home/dev/shot.png")
    }

    /// §1.5 — the boundary rule: mid-word slashes never linkify.
    @Test func midWordSlashDoesNotLinkify() {
        #expect(detected("a/b.png").isEmpty)
        #expect(detected("x(y/z.png)").isEmpty)
        #expect(detected("C:\\Users\\dev\\shot.png").isEmpty)
    }

    /// §1.5 — the boundary rule: after a space, newline, tab or opening paren/bracket/quote
    /// the path does linkify.
    @Test func boundaryCharactersAllowLocalPaths() {
        #expect(localPath(in: " /tmp/a.png") == "/tmp/a.png")
        #expect(localPath(in: "(/tmp/a.png)") == "/tmp/a.png")
        #expect(localPath(in: "[/tmp/a.png]") == "/tmp/a.png")
        #expect(localPath(in: "\"/tmp/a.png\"") == "/tmp/a.png")
        #expect(localPath(in: "'/tmp/a.png'") == "/tmp/a.png")
        #expect(localPath(in: "\n/tmp/a.png") == "/tmp/a.png")
        #expect(localPath(in: "\t/tmp/a.png") == "/tmp/a.png")
        #expect(localPath(in: "/tmp/a.png") == "/tmp/a.png") // start of text
    }

    /// §1.5 — relative paths never match.
    @Test func relativePathsNeverMatch() {
        #expect(detected("shots/a.png").isEmpty)
        #expect(detected("./shots/a.png").isEmpty)
        #expect(detected("../shots/a.png").isEmpty)
    }

    /// §1.5 — the minimum length is 2.
    @Test func localPathMinimumLength() {
        #expect(detected("/").map { $0 }.isEmpty)
    }

    /// §1.5 — inline code and fences are untouched.
    @Test func localPathInCodeZonesIsIgnored() {
        #expect(detected("`/tmp/a.png`").isEmpty)
        #expect(detected("```\n/tmp/a.png\n```").isEmpty)
    }

    /// §1.5 — `isLocalImagePath` ignores query/fragment handling entirely:
    /// the path must *end* with the extension, so a query disqualifies it.
    @Test func isLocalImagePathHasNoQueryHandling() {
        #expect(RichContentDetector.isLocalImagePath("/tmp/a.png"))
        #expect(RichContentDetector.isLocalImagePath("~/a.svg"))
        #expect(!RichContentDetector.isLocalImagePath("/tmp/a.png?w=1"))
        #expect(!RichContentDetector.isLocalImagePath("/tmp/a.png#f"))
        #expect(!RichContentDetector.isLocalImagePath("/tmp/a.txt"))
        #expect(!RichContentDetector.isLocalImagePath("relative/a.png"))
    }

    /// §1.5 — `isLocalPath` covers both kinds of bare path.
    @Test func isLocalPathHelper() {
        #expect(RichContentDetector.isLocalPath("/tmp/a.png"))
        #expect(RichContentDetector.isLocalPath("~/a.png"))
        #expect(!RichContentDetector.isLocalPath("a/b.png"))
    }

    // MARK: §1.6 — raw SVG blocks

    /// §1.6 — a literal inline SVG block is detected as raw SVG with its source.
    @Test func rawSVGBlockDetected() throws {
        let svg = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
        let source = "here is a chart \(svg) inline"
        let blocks = detected(source)
        let block = try #require(blocks.first)
        guard case .rawSVG(let raw, _) = block else {
            Issue.record("expected .rawSVG, got \(block)")
            return
        }
        #expect(raw == svg)
    }

    /// §1.6 — the SVG is case-insensitive and attributes can contain newlines.
    @Test func rawSVGCaseInsensitivityAndNewlineAttributes() throws {
        let svg = "<SVG\nviewBox=\"0 0 10 10\">\n<rect width=\"10\" height=\"10\"/>\n</SVG>"
        let blocks = detected(svg)
        guard case .rawSVG(let raw, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(raw == svg)
    }

    /// §1.6 — an unclosed `<svg` (streaming) stays text.
    @Test func unclosedSVGStaysText() {
        #expect(detected("<svg viewBox=\"0 0 10 10\"><rect").isEmpty)
    }

    /// §1.6 — attributes containing `<>` never match; the block stays text.
    @Test func svgWithAngleBracketsInAttributesStaysText() {
        #expect(detected("<svg data-x=\"<b>\"></svg>").isEmpty)
    }

    /// §1.6 — the 100 KiB cap keeps oversized blocks as text.
    @Test func oversizedSVGStaysText() {
        let payload = String(repeating: "x", count: 101 * 1024)
        let source = "<svg viewBox=\"0 0 10 10\">\(payload)</svg>"
        #expect(detected(source).isEmpty)
    }

    /// §1.6 — just under the cap is still detected.
    @Test func svgJustUnderCapIsDetected() throws {
        let payload = String(repeating: "x", count: 99 * 1024)
        let source = "<svg viewBox=\"0 0 10 10\">\(payload)</svg>"
        let blocks = detected(source)
        #expect(blocks.count == 1)
    }

    /// §1.6 — fenced code and inline code protect the SVG; it stays text.
    @Test func rawSVGInCodeZonesStaysText() {
        #expect(detected("```\n<svg></svg>\n```").isEmpty)
        #expect(detected("`<svg><rect/></svg>`").isEmpty)
    }

    /// §1.6 — URLs inside an SVG block are not double-reported by other stages.
    @Test func rawSVGContentsAreNotScannedByOtherStages() throws {
        let svg = #"<svg viewBox="0 0 10 10"><image href="https://example.com/a.png" width="1" height="1"/></svg>"#
        let blocks = detected(svg)
        let block = try #require(blocks.first)
        guard case .rawSVG = block else { Issue.record(); return }
        #expect(blocks.count == 1)
    }

    // MARK: §2 — visualize fences

    /// §2 fence detection — an explicit ` ```visualize ` fence hosts the stage;
    /// the block carries the fence body.
    @Test func visualizeFenceYieldsBlock() throws {
        let source = "```visualize\n<style>p{color:red}</style><p>hi</p>\n```"
        let blocks = detected(source)
        #expect(blocks.count == 1)
        guard case .visualize(let code, let range) = try #require(blocks.first) else {
            Issue.record("expected .visualize, got \(blocks)")
            return
        }
        #expect(code == "<style>p{color:red}</style><p>hi</p>")
        #expect(String(source[range]) == source)
    }

    /// §2 — an unclosed fence is EOF-terminated and still yields a block
    /// (streaming paints partial and settles; the stale "stays markdown" comment
    /// in the spec does not win over `viz.test.ts`).
    @Test func unclosedVisualizeFenceYieldsBlock() throws {
        let blocks = detected("```visualize\n<p>partial")
        #expect(blocks.count == 1)
        guard case .visualize(let code, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(code == "<p>partial")
    }

    /// §2 — fence lang is case-insensitive.
    @Test func visualizeFenceLangIsCaseInsensitive() throws {
        let blocks = detected("```Visualize\n<p>x</p>\n```")
        guard case .visualize = try #require(blocks.first) else {
            Issue.record();return
        }
    }

    /// §2 — a fence with a blank body renders nothing; detection reports nothing.
    @Test func visualizeFenceWithBlankBodyYieldsNothing() {
        #expect(detected("```visualize\n```").isEmpty)
        #expect(detected("```visualize\n   \n```").isEmpty)
    }

    /// §2 — URLs inside a visualize fence are not double-reported by other stages.
    @Test func visualizeFenceContentsAreNotScanned() throws {
        let source = "```visualize\n<img src=\"https://example.com/a.png\">\n```"
        let blocks = detected(source)
        try #require(blocks.count == 1)
        guard case .visualize = blocks[0] else { Issue.record(); return }
    }

    /// §2/§1.8 — fences we don't host produce nothing. (Mermaid moved out: G4 detects
    /// closed ```mermaid fences; see MermaidDetectorTests.)
    @Test func otherFencesYieldNothing() {
        #expect(detected("```yaml\nx: https://example.com/a.png\n```").isEmpty)
    }

    // MARK: pipeline order and ordering

    /// §1.4/§1.5/§1.6 — raw SVG is claimed before the URL scans see inside it,
    /// and document order is preserved across kinds.
    @Test func blocksAreDocumentOrdered() throws {
        let svg = #"<svg viewBox="0 0 1 1"></svg>"#
        let source = "https://a.test/x\n\n\(svg)\n\n/tmp/pic.png"
        let blocks = detected(source)
        try #require(blocks.count == 3)
        #expect(blocks.map { $0.range.lowerBound } == blocks.map { $0.range.lowerBound }.sorted())
        if case .linkCard = blocks[0] {} else { Issue.record("\(blocks[0])") }
        if case .rawSVG = blocks[1] {} else { Issue.record("\(blocks[1])") }
        if case .localImage = blocks[2] {} else { Issue.record("\(blocks[2])") }
    }

    // MARK: robustness — CRLF line endings

    /// CRLF — lines, fences and blocks behave exactly as with LF.
    @Test func crlfVisualizeFenceYieldsBlock() throws {
        let source = "```visualize\r\n<style>p{}</style><p>x</p>\r\n```\r\n"
        let blocks = detected(source)
        let block = try #require(blocks.first)
        guard case .visualize(let code, _) = block else {
            Issue.record("expected .visualize, got \(block)")
            return
        }
        #expect(code == "<style>p{}</style><p>x</p>")
    }

    /// CRLF — cards and players are detected on their own lines.
    @Test func crlfCardAndPlayerDetected() throws {
        let source = "https://a.test/x\r\n\r\nhttps://youtu.be/dQw4w9WgXcQ\r\n"
        let blocks = detected(source)
        let card = blocks.first { if case .linkCard = $0 { true } else { false } }
        let player = blocks.first { if case .youTubePlayer = $0 { true } else { false } }
        #expect(card != nil)
        #expect(player != nil)
    }

    /// CRLF — local image path on its own line.
    @Test func crlfLocalImageDetected() throws {
        let blocks = detected("/tmp/pic.png\r\n")
        guard case .localImage = try #require(blocks.first) else {
            Issue.record();return
        }
    }

    /// CRLF — a fence body carries no stray \r.
    @Test func crlfYoutubeFenceBodyIsClean() throws {
        let source = "```youtube\r\nhttps://youtu.be/dQw4w9WgXcQ\r\n```\r\n"
        let blocks = detected(source)
        guard case .youTubePlayer(let ref, _) = try #require(blocks.first) else {
            Issue.record();return
        }
        #expect(ref.id == "dQw4w9WgXcQ")
    }

    // MARK: helpers under test

    /// §1.4 — `trimTrailingPunctuation` strips exactly `.,;:!?`.
    @Test func trimTrailingPunctuationHelper() {
        #expect(RichContentDetector.trimTrailingPunctuation("abc.,;:!?") == "abc")
        #expect(RichContentDetector.trimTrailingPunctuation("abc") == "abc")
        #expect(RichContentDetector.trimTrailingPunctuation("a.b.c") == "a.b.c")
        #expect(RichContentDetector.trimTrailingPunctuation("...") == "")
    }

    // MARK: test helpers

    private func hasCard(_ source: String) -> Bool {
        detected(source).contains { if case .linkCard = $0 { true } else { false } }
    }

    private func bareImageURL(in source: String) -> String? {
        detected(source).compactMap { if case .bareImageURL(let url, _) = $0 { url } else { nil } }.first
    }

    private func localPath(in source: String) -> String? {
        detected(source).compactMap {
            switch $0 {
            case .localImage(let path, _, _): path
            case .localFileLink(let path, _): path
            default: nil
            }
        }.first
    }

    private func isImageURL(_ url: String) -> Bool {
        RichContentDetector.isRemoteImageURL(url)
    }
}
