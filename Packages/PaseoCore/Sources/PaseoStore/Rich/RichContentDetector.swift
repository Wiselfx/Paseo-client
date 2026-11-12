import Foundation

// Rich content detection for assistant Markdown. Pure text analysis, no networking:
// the UI owns metadata fetching (link cards) and daemon acquisition (local images).
//
// Encodes the detection rules from docs/research/05-rich-media-spec.md. There is no
// mdast on Linux without a dependency, so the paragraph model is built from lines and
// the list/heading "any depth" nesting is honoured through blockquote markers and the
// CommonMark ≤3-space indent rule (deeper nesting is not tracked — noted honestly).
// Authored links and images keep their source; only detection happens here.
// The raw-SVG 100 KiB cap is measured in UTF-8 bytes (the fork uses JS UTF-16 length).

/// One piece of rich content detected in assistant Markdown, in document order.
/// `range` indexes into the source string passed to `RichContentDetector.detect(in:)`.
public enum RichContentBlock: Sendable, Equatable {
    /// §1.1 — a bare URL alone on its line (never inside a list item or heading, and
    /// never when the paragraph also contains an authored link/image/code). The UI
    /// renders a favicon + domain + trimmed-URL card.
    case linkCard(url: String, range: Range<String.Index>)
    /// §1.2 — a full-width YouTube player: the `youtube` fence, a standalone bare
    /// URL/ID line in a pure-text paragraph, or a block that is solely one authored
    /// link to a YouTube video.
    case youTubePlayer(YouTubeReference, range: Range<String.Index>)
    /// §1.2 — a prose-sized player at an exact source range: a YouTube URL inside a
    /// sentence, or an authored link to YouTube inside a larger block. `url` keeps the
    /// query string (`?t=30` rides along); trailing `.,;:!?)]}>"'` stay in prose.
    case youTubeInline(YouTubeReference, range: Range<String.Index>)
    /// §1.4 — a bare remote image URL, trailing punctuation already stripped. Renders
    /// as an image, not a link.
    case bareImageURL(url: String, range: Range<String.Index>)
    /// C2 — two or more adjacent image blocks separated only by blank text, in
    /// document order. Ranges from the first block's start to the last block's end.
    case imageGroup(images: [RichImage], range: Range<String.Index>)
    /// §1.5 — a bare absolute or `~/` image path; `alt` is the basename. The UI
    /// resolves the path through the daemon (never reads the file directly).
    case localImage(path: String, alt: String, range: Range<String.Index>)
    /// §1.5 — a bare absolute or `~/` non-image path → a `file://` link that opens
    /// the file preview.
    case localFileLink(path: String, range: Range<String.Index>)
    /// §1.6 — a raw inline `<svg>…</svg>` block, at most `RichContentDetector.rawSVGMaxLength`
    /// bytes. Scripts never run (image context); unclosed blocks stay text.
    case rawSVG(source: String, range: Range<String.Index>)
    /// §2 — a ` ```visualize ` fence with a non-blank body: a self-contained HTML
    /// fragment hosting the sandboxed stage. Unclosed (streaming) fences are detected.
    case visualize(code: String, range: Range<String.Index>)
    /// C9 — a closed ` ```mermaid ` fence with a non-blank body: a diagram the client
    /// renders natively. A streaming (unclosed) fence stays a code block until it closes.
    case mermaid(source: String, range: Range<String.Index>)
    /// M17 — a standalone line that is exactly a coordinate pair (`lat, lng`), a `geo:`
    /// URI, or an Apple/Google Maps URL. Doc 05 specifies no map rule, so this is the
    /// strict §1.1-shaped rule: standalone line only, never inside lists/headings, and
    /// no address guessing — prose never becomes a map. The UI renders a MapKit
    /// snapshot that opens Apple Maps.
    case mapCard(MapReference, range: Range<String.Index>)
}

/// A map reference from a standalone coordinate line or maps URL. `latitude`/`longitude`
/// are nil only for query-only maps URLs whose coordinates cannot be read; the UI then
/// renders a calm placeholder card that still opens the URL.
public struct MapReference: Sendable, Equatable {
    /// The matched source text (or URL).
    public var url: String
    public var latitude: Double?
    public var longitude: Double?
    public init(url: String, latitude: Double?, longitude: Double?) {
        self.url = url
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The source range of the block, for document ordering and splicing.
public extension RichContentBlock {
    var range: Range<String.Index> {
        switch self {
        case .linkCard(_, let range),
             .youTubePlayer(_, let range),
             .youTubeInline(_, let range),
             .bareImageURL(_, let range),
             .imageGroup(_, let range),
             .localImage(_, _, let range),
             .localFileLink(_, let range),
             .rawSVG(_, let range),
             .visualize(_, let range),
             .mermaid(_, let range),
             .mapCard(_, let range):
            range
        }
    }
}

/// A YouTube video reference. `url` is the matched source text it was detected from:
/// the full URL (with any query string) for in-prose and standalone detections, the
/// link target for authored links, and the trimmed fence body for `youtube` fences.
/// Build embed/watch/poster URLs from `id`.
public struct YouTubeReference: Sendable, Equatable {
    /// The 11-character video ID.
    public var id: String
    public var url: String
    public init(id: String, url: String) { self.id = id; self.url = url }
}

/// A YouTube URL found inside prose (§1.2 `findYouTubeUrls`), with its absolute range.
public struct YouTubeURLHit: Sendable, Equatable {
    public var url: String
    public var id: String
    public var range: Range<String.Index>
    public init(url: String, id: String, range: Range<String.Index>) {
        self.url = url
        self.id = id
        self.range = range
    }
}

/// Detects rich content in assistant Markdown (the §1 kinds and the §2 viz fence).
/// All functions are pure; nothing touches the network or disk.
public enum RichContentDetector {
    /// §1.6 — `RAW_SVG_MAX_CHARS`. Blocks larger than this stay text.
    public static let rawSVGMaxLength = 100 * 1024

    // MARK: - Public API

    /// Every rich-content block in document order.
    public static func detect(in source: String) -> [RichContentBlock] {
        var blocks: [RichContentBlock] = []

        // Fenced code blocks are cut out first: they are protected zones for every
        // other stage, and the two fence kinds we host become blocks here.
        let fences = scanFences(in: source)
        for fence in fences {
            let info = fence.info.trimmingCharacters(in: .whitespaces).lowercased()
            switch info {
            case "visualize":
                // §2 — fence value must be non-blank or the fence renders nothing.
                if !fence.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.visualize(code: fence.body, range: fence.range))
                }
            case "mermaid":
                // C9 — closed fences only: a streaming fence stays a code block, so the
                // half-written diagram never flashes or errors mid-stream.
                if fence.closed
                    && !fence.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    blocks.append(.mermaid(source: fence.body, range: fence.range))
                }
            case "youtube":
                // §1.2 — fence body is a watch URL or a bare ID. An unparseable body
                // renders nothing at the UI, so detection reports nothing either.
                let body = fence.body.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = youtubeID(for: body) {
                    blocks.append(.youTubePlayer(YouTubeReference(id: id, url: body), range: fence.range))
                }
            default:
                break
            }
        }
        let fenceRanges = mergeRanges(fences.map(\.range))

        // Raw SVG (§1.6) — first pre-pass: the whole block rides the image pipeline.
        // Its protected zones are fences and inline code (§1.6), so code spans are
        // computed against fences alone first.
        let codeSpansForSVG = scanInlineCodeSpans(in: source, outside: fenceRanges)
        let svgs = scanRawSVGs(in: source, outside: mergeRanges(fenceRanges + codeSpansForSVG))
        blocks += svgs.map { RichContentBlock.rawSVG(source: String(source[$0]), range: $0) }

        // Inline code spans (§1.4 protected zones). Single-line and multi-line;
        // unpaired backtick runs are literal text and protect nothing.
        let protectedWithoutCode = mergeRanges(fenceRanges + svgs)
        let codeSpans = scanInlineCodeSpans(in: source, outside: protectedWithoutCode)

        // Authored links/images and autolinks (§1.4 protected zones) — they stay
        // visible to the YouTube stage (a link with a YouTube URL hosts an inline
        // player) but not to the image/path scans.
        let linkSpans = scanAuthoredLinks(in: source, outside: mergeRanges(protectedWithoutCode + codeSpans))

        // §1.4/§1.5 — bare remote image URLs and bare local paths, anywhere in prose.
        let scannerExclusions = mergeRanges(protectedWithoutCode + codeSpans + linkSpans.map(\.range))
        for segment in unprotectedSegments(source, excluding: scannerExclusions) {
            scanBareImageURLs(in: segment, into: &blocks)
            scanLocalPaths(in: segment, into: &blocks)
        }

        // §1.1/§1.2 — paragraph-aware detection (link cards and YouTube players).
        // Fences act as block separators; code spans and raw SVG stay visible for
        // purity, but their contents are never scanned themselves.
        blocks += paragraphBlocks(
            in: source,
            outside: fenceRanges,
            purityExclusions: mergeRanges(codeSpans + svgs + linkSpans.map(\.range)),
            linkSpans: linkSpans)

        return blocks.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Splits `source` into block-level units for incremental prose rendering
    /// (upstream `f35b0b8b7`): paragraphs, headings, lists and quotes become
    /// individual ranges, so a streamed token re-parses only the open unit.
    ///
    /// Blank lines separate units, with three exceptions that keep a unit whole:
    /// - fenced code blocks (``` or ~~~, including unclosed ones): a blank line
    ///   inside a fence is body text;
    /// - raw `<svg>…</svg>` blocks: one rich block, and it may contain blank lines;
    /// - a blank line inside a list (between items, or before an indented
    ///   continuation of an item): the list continues, so splitting there would
    ///   change tight/loose rendering.
    ///
    /// Ranges cover `source` except for whitespace-only spans, which are dropped.
    public static func splitIntoBlocks(_ source: String) -> [Range<String.Index>] {
        let lines = splitLines(source)
        var ranges: [Range<String.Index>] = []
        var currentStart = source.startIndex
        var openFence: (marker: Character, length: Int)?
        var inSVG = false
        var sawBlankRun = false
        /// True while the last non-blank line belongs to a list item (a marker line,
        /// an indented continuation, or a lazy paragraph continuation of one).
        var inList = false

        for line in lines {
            let text = source[line.range]
            let indent = leadingIndent(text)
            let isListItem = isListItem(text)

            if let fence = openFence {
                if isClosingFence(text, marker: fence.marker, length: fence.length) {
                    openFence = nil
                }
            } else if let opened = openingFence(text) {
                openFence = (opened.marker, opened.length)
            }
            let inFence = openFence != nil

            // Raw SVG is tracked only outside fences: a `<svg>` in a code sample is
            // body text, not a rich block.
            if !inFence {
                if inSVG {
                    if closesSVG(text) { inSVG = false }
                } else if opensSVG(text) && !closesSVG(text) {
                    inSVG = true
                }
            }

            let isBlank = text.allSatisfy { $0.isWhitespace }
            if isBlank {
                if !inFence && !inSVG { sawBlankRun = true }
                continue
            }

            if sawBlankRun {
                let continuesList = inList && (isListItem || indent >= 2)
                if !continuesList {
                    ranges.append(currentStart..<line.range.lowerBound)
                    currentStart = line.range.lowerBound
                    inList = false
                }
                sawBlankRun = false
            }

            if !inFence {
                if isListItem {
                    inList = true
                } else if inList && (indent >= 2 || !isParagraphBlockStarter(text)) {
                    // Indented or lazy continuation of the open list item.
                    inList = true
                } else {
                    inList = false
                }
            }
        }

        if currentStart < source.endIndex {
            ranges.append(currentStart..<source.endIndex)
        }
        return ranges.filter { range in
            !source[range].allSatisfy { $0.isWhitespace }
        }
    }

    /// §1.2 — `youtubeIdForUrl`: the 11-char ID from a watch/shorts/live/embed/youtu.be
    /// URL or a bare ID, or nil. Trims first. Streaming-safe: a partial ID never matches.
    public static func youtubeID(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isBareYouTubeID(trimmed) { return trimmed }
        return parseYouTubeMatch(in: trimmed[trimmed.startIndex...], from: trimmed.startIndex)?.id
    }

    /// §1.2 — `findYouTubeUrls`: every YouTube URL in prose, with exact ranges. The URL
    /// keeps consuming while it stays URL-ish, then trailing `.,;:!?)]}>"'` are stripped.
    /// Protected zones must be removed by the caller when they matter (or use
    /// `detect(in:)`, which handles this).
    public static func findYouTubeURLs(in text: String) -> [YouTubeURLHit] {
        youtubeHits(in: Substring(text))
    }

    /// §1.1 — `isRemoteImageUrl`: scheme matches `https?:|data:|blob:` (case-insensitive)
    /// and the part before `#` ends with an image extension (query string allowed).
    public static func isRemoteImageURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("data:") || lower.hasPrefix("blob:") else { return false }
        let beforeHash = lower[..<(lower.firstIndex(of: "#") ?? lower.endIndex)]
        if let query = beforeHash.firstIndex(of: "?") {
            return hasImageExtension(String(beforeHash[..<query]))
        }
        return hasImageExtension(String(beforeHash))
    }

    /// §1.5 — `isLocalImagePath`: absolute or `~/` path whose (punctuation-trimmed)
    /// ending carries an image extension, case-insensitive. No query/fragment handling.
    public static func isLocalImagePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else { return false }
        return hasImageExtension(trimTrailingPunctuation(trimmed.lowercased()))
    }

    /// `isLocalPath` (media-links.ts): absolute or home-relative, any kind.
    public static func isLocalPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~/")
    }

    /// `trimTrailingPunctuation`: strips trailing `.,;:!?` (sentences end, URLs don't).
    public static func trimTrailingPunctuation(_ s: String) -> String {
        String(s[..<trailingPunctuationEnd(s.startIndex..<s.endIndex, in: s, stoppingAt: [".", ",", ";", ":", "!", "?"])])
    }

    /// §1.1 — `domainForUrl`: scheme and port are stripped; userinfo is *not*.
    /// `https://user:pw@host/` yields `user`; `https://user@host/` yields `user@host`.
    public static func domain(for url: String) -> String {
        var rest = Substring(url)
        if let schemeEnd = url.range(of: "://"), isScheme(String(url[..<schemeEnd.lowerBound])) {
            rest = url[schemeEnd.upperBound...]
        }
        var host = Substring()
        for char in rest {
            if char == "/" || char == ":" || char == "?" || char == "#" || char.isWhitespace { break }
            host.append(char)
        }
        return host.isEmpty ? url : String(host)
    }

    /// §1.1 — `displayUrl`: scheme, userinfo, query, fragment and trailing slashes are
    /// stripped; host + path remain. For visible text only — loading always uses the
    /// full URL.
    public static func displayURL(_ url: String) -> String {
        guard let schemeEnd = url.range(of: "://"), isScheme(String(url[..<schemeEnd.lowerBound])) else {
            return url
        }
        var rest = url[schemeEnd.upperBound...]
        // Drop userinfo (`user:pw@` or `user@`).
        if let at = rest.firstIndex(of: "@"),
           !rest[..<at].contains(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0.isWhitespace }) {
            rest = rest[rest.index(after: at)...]
        }
        // Host runs to the first / ? # or whitespace.
        var hostEnd = rest.startIndex
        while hostEnd < rest.endIndex {
            let char = rest[hostEnd]
            if char == "/" || char == "?" || char == "#" || char.isWhitespace { break }
            hostEnd = rest.index(after: hostEnd)
        }
        let host = rest[..<hostEnd]
        // No path at all: host only.
        guard hostEnd < rest.endIndex, rest[hostEnd] == "/" else {
            return String(host)
        }
        let pathStart = rest.index(after: hostEnd)
        var pathEnd = pathStart
        while pathEnd < rest.endIndex {
            let char = rest[pathEnd]
            if char == "?" || char == "#" || char.isWhitespace { break }
            pathEnd = rest.index(after: pathEnd)
        }
        var path = rest[pathStart..<pathEnd]
        while path.last == "/" { path = path.dropLast() }
        if path.isEmpty { return String(host) }
        return String(host) + "/" + path
    }

    /// `youtubeEmbedUrl` (youtube/urls.ts) — nocookie embed, `rel=0`.
    public static func youTubeEmbedURL(id: String) -> String {
        "https://www.youtube-nocookie.com/embed/\(id)?rel=0"
    }

    /// `youtubeThumbnailUrl` (youtube/urls.ts) — hqdefault letterboxes 16:9 inside 4:3.
    public static func youTubeThumbnailURL(id: String) -> String {
        "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
    }

    /// `youtubeWatchUrl` (youtube/urls.ts).
    public static func youTubeWatchURL(id: String) -> String {
        "https://www.youtube.com/watch?v=\(id)"
    }

    /// M17 — a strict standalone map reference (the whole trimmed line): a `lat, lng`
    /// coordinate pair (decimal point required, latitude −90…90, longitude −180…180),
    /// a `geo:` URI, or an Apple/Google Maps URL. Anything looser — street addresses,
    /// coordinates in prose — is deliberately not a map: no fuzzy guessing.
    public static func mapReference(forLine line: String) -> MapReference? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("geo:") {
            guard let (lat, lng) = parseCoordinatePair(String(trimmed.dropFirst(4))) else { return nil }
            return MapReference(url: trimmed, latitude: lat, longitude: lng)
        }
        if let pair = parseCoordinatePair(trimmed) {
            return MapReference(url: trimmed, latitude: pair.0, longitude: pair.1)
        }
        guard isBareURLLineLike(trimmed) else { return nil }
        return mapReference(forURL: trimmed)
    }

    private static func isBareURLLineLike(_ line: String) -> Bool {
        let lower = line.lowercased()
        return (lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("maps:"))
            && !line.contains(where: { $0.isWhitespace })
    }

    /// `lat, lng` — both parts must be plain decimals (a decimal point is required so
    /// year pairs and fractions never match) and in range.
    private static func parseCoordinatePair(_ text: String) -> (Double, Double)? {
        let semicolonHead = text.split(separator: ";", omittingEmptySubsequences: true).first.map(String.init) ?? text
        let head = semicolonHead.split(separator: "&", omittingEmptySubsequences: false).first.map(String.init) ?? semicolonHead
        let parts = head.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let lat = parseDecimal(parts[0]), let lng = parseDecimal(parts[1]) else { return nil }
        guard (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        return (lat, lng)
    }

    private static func parseDecimal(_ part: Substring) -> Double? {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(".") else { return nil }
        var body = trimmed[...]
        if body.first == "-" || body.first == "+" { body = body.dropFirst() }
        guard !body.isEmpty,
            body.allSatisfy({ $0.isNumber || $0 == "." }),
            body.filter({ $0 == "." }).count == 1
        else { return nil }
        return Double(trimmed)
    }

    /// Apple Maps (`maps.apple.com`, `maps:?`) and Google Maps (`google.com/maps`,
    /// `maps.google.com`, `goo.gl/maps`) URLs; coordinates read from `ll=`, a numeric
    /// `q=`/`query=`, or the `@lat,lng` path form, when present.
    private static func mapReference(forURL url: String) -> MapReference? {
        let lower = url.lowercased()
        let apple = lower.contains("maps.apple.com") || lower.hasPrefix("maps:")
        let google = lower.contains("google.com/maps") || lower.contains("maps.google.com")
            || lower.contains("goo.gl/maps")
        guard apple || google else { return nil }
        var pair: (Double, Double)?
        if let range = lower.range(of: "ll="), let found = parseCoordinatePair(String(url[range.upperBound...])) {
            pair = found
        } else if let at = lower.firstIndex(of: "@") {
            // Google's @lat,lng,zoom form: only the first two numbers are coordinates.
            let tail = String(url[url.index(after: at)...])
            let firstTwo = tail.split(separator: ",", omittingEmptySubsequences: false)
                .prefix(2).joined(separator: ",")
            pair = parseCoordinatePair(firstTwo)
        } else {
            for key in ["q=", "query="] {
                if let range = lower.range(of: key),
                    let found = parseCoordinatePair(String(url[range.upperBound...]))
                {
                    pair = found
                    break
                }
            }
        }
        return MapReference(url: url, latitude: pair?.0, longitude: pair?.1)
    }
}

// MARK: - Shared helpers

private func isScheme(_ candidate: String) -> Bool {
    guard let first = candidate.first, first.isLetter else { return false }
    return candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
}

private func hasImageExtension(_ s: String) -> Bool {
    // REMOTE_IMAGE_RE / LOCAL_IMAGE_EXT_RE plus H5: `.avif`, `.heic` and `.heif` decode fine on
    // iOS but were never detected, so an agent's HEIC screenshot or AVIF export arrived as a
    // bare link. Upstream's list stays first for upstream parity.
    for ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".avif", ".heic", ".heif"]
    where s.hasSuffix(ext) {
        return true
    }
    return false
}

/// End index after stripping trailing characters in `stoppingAt`.
func trailingPunctuationEnd<S: StringProtocol>(_ range: Range<S.Index>, in text: S, stoppingAt characters: Set<Character>) -> S.Index {
    var end = range.upperBound
    while end > range.lowerBound {
        let previous = text.index(before: end)
        if characters.contains(text[previous]) { end = previous } else { break }
    }
    return end
}

private let trailingURLPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    var merged: [Range<String.Index>] = []
    for range in sorted {
        if let last = merged.last, last.upperBound >= range.lowerBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
        } else {
            merged.append(range)
        }
    }
    return merged
}

/// The pieces of `source` not covered by `excluded`, preserving absolute indices.
func unprotectedSegments(_ source: String, excluding excluded: [Range<String.Index>]) -> [Substring] {
    var segments: [Substring] = []
    var cursor = source.startIndex
    for range in mergeRanges(excluded) {
        if cursor < range.lowerBound { segments.append(source[cursor..<range.lowerBound]) }
        if range.upperBound > cursor { cursor = range.upperBound }
    }
    if cursor < source.endIndex { segments.append(source[cursor..<source.endIndex]) }
    return segments
}

func overlapsAny(_ range: Range<String.Index>, in ranges: [Range<String.Index>]) -> Bool {
    for candidate in mergeRanges(ranges) {
        if candidate.upperBound <= range.lowerBound { continue }
        if candidate.lowerBound >= range.upperBound { break }
        return true
    }
    return false
}

// MARK: - Lines and fences

struct SourceLine {
    var range: Range<String.Index>
}

func splitLines(_ source: String) -> [SourceLine] {
    var lines: [SourceLine] = []
    var start = source.startIndex
    var i = source.startIndex
    while i < source.endIndex {
        // Note: "\r\n" is a single grapheme cluster in Swift; lines are
        // terminated by LF, CRLF or a lone CR.
        if source[i] == "\n" || source[i] == "\r\n" || source[i] == "\r" {
            lines.append(SourceLine(range: start..<i))
            i = source.index(after: i)
            start = i
        } else {
            i = source.index(after: i)
        }
    }
    if start < source.endIndex { lines.append(SourceLine(range: start..<source.endIndex)) }
    return lines
}


/// Fenced code blocks (``` or ~~~, including unclosed → EOF). Fence lines are
/// complete lines, so outside segments always split on line boundaries.
/// The fence body is the lines between its markers, rejoined with `\n`
/// (keeping indices into the source for the fence's own range).
private func fenceBody(_ source: String, lines: [SourceLine], from: Int, to: Int) -> String {
    guard from < to, from >= 0, to <= lines.count else { return "" }
    return lines[from..<to].map { String(source[$0.range]) }.joined(separator: "\n")
}

func scanFences(in source: String) -> [Fence] {
    let lines = splitLines(source)
    var fences: [Fence] = []
    var open: (marker: Character, length: Int, start: Int, info: String)?

    for (index, line) in lines.enumerated() {
        let text = source[line.range]
        if let current = open {
            if isClosingFence(text, marker: current.marker, length: current.length) {
                let body = fenceBody(source, lines: lines, from: current.start + 1, to: index)
                fences.append(Fence(range: lines[current.start].range.lowerBound..<line.range.upperBound, info: current.info, body: body, closed: true))
                open = nil
            }
            continue
        }
        if let candidate = openingFence(text) {
            open = (candidate.marker, candidate.length, index, candidate.info)
        }
    }
    if let current = open {
        let body = fenceBody(source, lines: lines, from: current.start + 1, to: lines.count)
        fences.append(Fence(range: lines[current.start].range.lowerBound..<source.endIndex, info: current.info, body: body, closed: false))
    }
    return fences.sorted { $0.range.lowerBound < $1.range.lowerBound }
}

struct Fence {
    var range: Range<String.Index>
    var info: String
    var body: String
    /// True when a closing fence terminated the block. Unclosed (streaming) fences run
    /// to the end of input; only hosts that render partial content claim them.
    var closed: Bool
}

private func openingFence<S: StringProtocol>(_ line: S) -> (marker: Character, length: Int, info: String)? {
    var i = line.startIndex
    var indent = 0
    while i < line.endIndex && line[i] == " " && indent < 4 {
        indent += 1
        i = line.index(after: i)
    }
    if indent > 3 { return nil }
    guard i < line.endIndex, line[i] == "`" || line[i] == "~" else { return nil }
    let marker = line[i]
    var j = i
    var length = 0
    while j < line.endIndex && line[j] == marker {
        length += 1
        j = line.index(after: j)
    }
    if length < 3 { return nil }
    let info = String(line[j...]).trimmingCharacters(in: .whitespaces)
    // A backtick fence's info string may not contain a backtick (CommonMark).
    if marker == "`" && info.contains("`") { return nil }
    return (marker, length, info)
}

private func isClosingFence(_ line: Substring, marker: Character, length: Int) -> Bool {
    var i = line.startIndex
    var indent = 0
    while i < line.endIndex && line[i] == " " && indent < 4 {
        indent += 1
        i = line.index(after: i)
    }
    if indent > 3 { return false }
    var j = i
    var count = 0
    while j < line.endIndex && line[j] == marker {
        count += 1
        j = line.index(after: j)
    }
    if count < length { return false }
    while j < line.endIndex {
        if line[j] != " " && line[j] != "\t" { return false }
        j = line.index(after: j)
    }
    return true
}

// MARK: - Raw SVG (§1.6)

/// `<svg(?:\s[^<>]*)?>…</svg\s*>` — case-insensitive, non-greedy; attributes may not
/// contain `<>`; the cap keeps oversized blocks as text; unclosed blocks stay text.
/// Protected zones for this pre-pass: fences and inline code only.
func scanRawSVGs(in source: String, outside excluded: [Range<String.Index>]) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    for segment in unprotectedSegments(source, excluding: excluded) {
        var search = segment.startIndex
        while search < segment.endIndex {
            guard let start = nextCaseInsensitive(segment, "<svg", from: search) else { break }
            var claimed = false
            if let match = matchRawSVG(segment, from: start) {
                if String(segment[match]).utf8.count <= RichContentDetector.rawSVGMaxLength {
                    found.append(match)
                    search = match.upperBound
                    claimed = true
                }
            }
            if !claimed {
                // Oversized or unterminated: stays text. Keep scanning past `<svg`
                // in case a later, valid block starts inside this one.
                search = segment.index(after: start)
            }
        }
    }
    return found
}

func matchRawSVG(_ text: Substring, from start: Substring.Index) -> Range<String.Index>? {
    var i = text.index(start, offsetBy: 4)
    if i < text.endIndex && text[i] == ">" {
        i = text.index(after: i)
    } else {
        guard i < text.endIndex, text[i].isWhitespace else { return nil }
        var terminated = false
        while i < text.endIndex {
            let char = text[i]
            if char == ">" {
                i = text.index(after: i)
                terminated = true
                break
            }
            if char == "<" { return nil }
            i = text.index(after: i)
        }
        if !terminated { return nil }
    }
    var search = i
    while let close = nextCaseInsensitive(text, "</svg", from: search) {
        var j = text.index(close, offsetBy: 5)
        while j < text.endIndex && text[j].isWhitespace { j = text.index(after: j) }
        if j < text.endIndex && text[j] == ">" {
            return start..<text.index(after: j)
        }
        search = text.index(after: close) // invalid close: keep looking
    }
    return nil
}

func nextCaseInsensitive(_ text: Substring, _ needle: String, from start: Substring.Index) -> Substring.Index? {
    var i = start
    let lowered = needle.lowercased()
    guard let first = lowered.first else { return nil }
    let firstLower = String(first).lowercased()
    while i < text.endIndex {
        if String(text[i]).lowercased() == firstLower {
            let candidate = text[i...]
            if candidate.count >= lowered.count,
               candidate.prefix(lowered.count).lowercased() == lowered {
                return i
            }
        }
        i = text.index(after: i)
    }
    return nil
}

// MARK: - Inline code spans (§1.4 protected zones)

/// `` ` `` runs pair with the next run of equal length; content may span lines.
/// Unpaired runs are literal text and protect nothing. Runs inside fences never
/// reach this scan (fences are excluded first).
func scanInlineCodeSpans(in source: String, outside excluded: [Range<String.Index>]) -> [Range<String.Index>] {
    var spans: [Range<String.Index>] = []
    for segment in unprotectedSegments(source, excluding: excluded) {
        var runs: [(range: Range<String.Index>, length: Int)] = []
        var i = segment.startIndex
        while i < segment.endIndex {
            if segment[i] == "`" {
                let runStart = i
                var j = i
                while j < segment.endIndex && segment[j] == "`" { j = segment.index(after: j) }
                runs.append((runStart..<j, segment.distance(from: runStart, to: j)))
                i = j
            } else {
                i = segment.index(after: i)
            }
        }
        var k = 0
        while k < runs.count {
            var matched = -1
            var m = k + 1
            while m < runs.count {
                if runs[m].length == runs[k].length { matched = m; break }
                m += 1
            }
            if matched != -1 {
                spans.append(runs[k].range.lowerBound..<runs[matched].range.upperBound)
                k = matched + 1
            } else {
                k += 1
            }
        }
    }
    return mergeRanges(spans)
}

// MARK: - Authored links, images and autolinks (§1.4 protected zones)

struct LinkSpan {
    var range: Range<String.Index>
    /// The link destination (no title, angle brackets stripped).
    var url: String?
    var isImage: Bool
    var isAutolink: Bool
}

func scanAuthoredLinks(in source: String, outside excluded: [Range<String.Index>]) -> [LinkSpan] {
    var spans: [LinkSpan] = []
    for segment in unprotectedSegments(source, excluding: excluded) {
        var i = segment.startIndex
        while i < segment.endIndex {
            let char = segment[i]
            if char == "<" {
                // Autolink: `<` + non-space run + `>`.
                let contentStart = segment.index(after: i)
                var j = contentStart
                while j < segment.endIndex && !segment[j].isWhitespace && segment[j] != ">" {
                    j = segment.index(after: j)
                }
                if j < segment.endIndex && segment[j] == ">" && j > contentStart {
                    spans.append(LinkSpan(range: i..<segment.index(after: j), url: String(segment[contentStart..<j]), isImage: false, isAutolink: true))
                    i = segment.index(after: j)
                } else {
                    i = segment.index(after: i)
                }
                continue
            }
            let isImage = char == "!"
            let bracketStart: Substring.Index
            if isImage {
                let next = segment.index(after: i)
                if next < segment.endIndex && segment[next] == "[" {
                    bracketStart = next
                } else {
                    i = segment.index(after: i)
                    continue
                }
            } else if char == "[" {
                bracketStart = i
            } else {
                i = segment.index(after: i)
                continue
            }
            // Alt/text: no `[`, `]` or newline inside.
            var j = segment.index(after: bracketStart)
            var altEnd: Substring.Index?
            while j < segment.endIndex {
                let altChar = segment[j]
                if altChar == "]" { altEnd = j; break }
                if altChar == "[" || altChar == "\n" { break }
                j = segment.index(after: j)
            }
            guard let altEnd else { i = segment.index(after: i); continue }
            let parenOpen = segment.index(after: altEnd)
            guard parenOpen < segment.endIndex, segment[parenOpen] == "(" else {
                i = segment.index(after: i)
                continue
            }
            var k = segment.index(after: parenOpen)
            var parenEnd: Substring.Index?
            while k < segment.endIndex {
                let inner = segment[k]
                if inner == ")" { parenEnd = k; break }
                if inner == "(" || inner == "\n" { break }
                k = segment.index(after: k)
            }
            guard let parenEnd else { i = segment.index(after: i); continue }
            let innerText = String(segment[segment.index(after: parenOpen)..<parenEnd]).trimmingCharacters(in: .whitespaces)
            // Destination = up to the first whitespace (an optional "title" may follow);
            // <> around the destination are allowed by CommonMark.
            let destination = innerText.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            let url = destination.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }
            spans.append(LinkSpan(range: i..<segment.index(after: parenEnd), url: url, isImage: isImage, isAutolink: false))
            i = segment.index(after: parenEnd)
        }
    }
    return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
}

// MARK: - Bare image URLs (§1.4)

/// `https?://…` in prose, trailing `.,;:!?` stripped, kept iff `isRemoteImageURL`.
/// Fences, inline code, authored links/images, autolinks and raw SVG never reach here.
///
/// Parens are URL characters, and Wikipedia's file names are full of them
/// (`Rotating_earth_(large).gif`), while `isBareURLChar` stops at `)`. A paren the URL opened
/// itself extends the run to its partner; a paren the sentence opened (`see https://x/a.png)`)
/// still ends it. Only this image scanner does that: it is the one place a `)` cannot be
/// punctuation mid-URL.
func scanBareImageURLs(in segment: Substring, into blocks: inout [RichContentBlock]) {
    var i = segment.startIndex
    while i < segment.endIndex {
        guard let start = nextHTTPScheme(segment, from: i) else { return }
        var end = start
        var openParens = 0
        while end < segment.endIndex {
            let char = segment[end]
            if char == "(" {
                openParens += 1
            } else if char == ")" {
                guard openParens > 0 else { break }
                openParens -= 1
            } else if !isBareURLChar(char) {
                break
            }
            end = segment.index(after: end)
        }
        let trimEnd = trailingPunctuationEnd(start..<end, in: segment, stoppingAt: trailingURLPunctuation)
        let url = String(segment[start..<trimEnd])
        if !url.isEmpty && RichContentDetector.isRemoteImageURL(url) {
            blocks.append(.bareImageURL(url: url, range: start..<trimEnd))
        }
        i = end
    }
}

func nextHTTPScheme(_ text: Substring, from start: Substring.Index) -> Substring.Index? {
    var i = start
    while i < text.endIndex {
        let rest = text[i...]
        if rest.count >= 7,
           rest.prefix(7).lowercased() == "http://"
            || (rest.count >= 8 && rest.prefix(8).lowercased() == "https://") {
            return i
        }
        i = text.index(after: i)
    }
    return nil
}

private func isBareURLChar(_ char: Character) -> Bool {
    // BARE_URL_RE `[^\s<>)\]]+`
    if char.isWhitespace { return false }
    return char != "<" && char != ">" && char != ")" && char != "]"
}

// MARK: - Local paths (§1.5)

/// `(~?\/[^\s`'"[\]()<>]*)` with the boundary rule: the char before the match must be
/// start-of-text, space, \n, \t, `(`, `[`, `"` or `'`. Trailing `.,;:!?` is trimmed;
/// minimum length 2; image extensions become images (alt = basename), the rest
/// `file://` links. Relative and Windows drive paths never match.
func scanLocalPaths(in segment: Substring, into blocks: inout [RichContentBlock]) {
    var i = segment.startIndex
    while i < segment.endIndex {
        let char = segment[i]
        let matchStart: Substring.Index
        if char == "/" {
            matchStart = i
        } else if char == "~", segment.index(after: i) < segment.endIndex,
                  segment[segment.index(after: i)] == "/" {
            matchStart = i
        } else {
            i = segment.index(after: i)
            continue
        }
        // Boundary rule (media-links.ts `isPathStart`): the char before the match —
        // segment-relative, mirroring the fork — must be start-of-segment, space,
        // \n, \t, `(`, `[`, `"` or `'`.
        if matchStart > segment.startIndex {
            let before = segment[segment.index(before: matchStart)]
            let boundary = before == " " || before == "\n" || before == "\t"
                || before == "(" || before == "[" || before == "\"" || before == "'"
            if !boundary {
                i = segment.index(after: matchStart)
                continue
            }
        }
        var end = matchStart
        while end < segment.endIndex && isPathChar(segment[end]) {
            end = segment.index(after: end)
        }
        let trimEnd = trailingPunctuationEnd(matchStart..<end, in: segment, stoppingAt: trailingURLPunctuation)
        let raw = String(segment[matchStart..<trimEnd])
        guard raw.count >= 2 else {
            i = segment.index(after: i) // lone slash: not a path
            continue
        }
        if RichContentDetector.isLocalImagePath(raw) {
            let base = raw.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? raw
            blocks.append(.localImage(path: raw, alt: base, range: matchStart..<trimEnd))
        } else {
            blocks.append(.localFileLink(path: raw, range: matchStart..<trimEnd))
        }
        i = trimEnd
    }
}

private func isPathChar(_ char: Character) -> Bool {
    if char.isWhitespace { return false }
    return !"`'\"[]()<>".contains(char)
}

// MARK: - YouTube (§1.2)

private let youTubeIDCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
private let youTubeTrailingPunctuation = Set(".,;:!?)]}>\"'")

func isBareYouTubeID<S: StringProtocol>(_ s: S) -> Bool {
    s.count == 11 && s.allSatisfy { youTubeIDCharacters.contains($0) }
}

private func isYouTubeURLChar(_ char: Character) -> Bool {
    // URL_CHAR_RE `[^\s"'`<>*]`
    if char.isWhitespace { return false }
    return !"\"'`<>*".contains(char)
}

private func isSchemeLength(_ text: Substring, at index: Substring.Index) -> Int {
    let rest = text[index...]
    if rest.count >= 7, rest.prefix(7).lowercased() == "http://" { return 7 }
    if rest.count >= 8, rest.prefix(8).lowercased() == "https://" { return 8 }
    return 0
}

private func isValidSubdomainLabel(_ label: Substring) -> Bool {
    !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
}

/// 11 `[A-Za-z0-9_-]` chars with a `(?![A-Za-z0-9_-])` tail guard.
private func youTubeIDEnd(at start: Substring.Index, in text: Substring) -> Substring.Index? {
    var i = start
    var count = 0
    while i < text.endIndex && count < 11 {
        guard youTubeIDCharacters.contains(text[i]) else { return nil }
        count += 1
        i = text.index(after: i)
    }
    if count != 11 { return nil }
    if i < text.endIndex && youTubeIDCharacters.contains(text[i]) { return nil } // tail guard
    return i
}

/// Manual port of `YOUTUBE_ID_RE` (case-insensitive): optional single subdomain label,
/// `youtube(-nocookie)?.com/(watch?…v=|shorts/|live/|embed/)` or `youtu.be/`, then 11 ID
/// characters with a tail guard. `watch` allows `v=` at any position in the query.
/// Returns the ID and the end of the ID (exclusive), at or after `from`.
func parseYouTubeMatch(in text: Substring, from start: Substring.Index) -> (id: String, idEnd: Substring.Index, matchStart: Substring.Index)? {
    var search = start
    while search < text.endIndex {
        let schemeLength = isSchemeLength(text, at: search)
        guard schemeLength > 0 else {
            search = text.index(after: search)
            continue
        }
        let afterScheme = text.index(search, offsetBy: schemeLength)
        // Host: up to the next `/` or the end.
        var hostEnd = afterScheme
        while hostEnd < text.endIndex, text[hostEnd] != "/" {
            if text[hostEnd].isWhitespace || text[hostEnd] == "?" || text[hostEnd] == "#" { break }
            hostEnd = text.index(after: hostEnd)
        }
        guard hostEnd < text.endIndex, text[hostEnd] == "/" else {
            search = text.index(after: search)
            continue
        }
        let host = String(text[afterScheme..<hostEnd]).lowercased()
        let hostParts = host.split(separator: ".", omittingEmptySubsequences: false)
        let youtubeCom: (Substring, Substring) = ("youtube", "com")
        let noCookie: (Substring, Substring) = ("youtube-nocookie", "com")
        let youtuBe: (Substring, Substring) = ("youtu", "be")
        func pairMatches(_ a: Substring, _ b: Substring, _ pair: (Substring, Substring)) -> Bool {
            a == pair.0 && b == pair.1
        }
        var isYouTubeHost = false
        var isYouTubeBe = false
        switch hostParts.count {
        case 2:
            isYouTubeHost = pairMatches(hostParts[0], hostParts[1], youtubeCom) || pairMatches(hostParts[0], hostParts[1], noCookie)
            isYouTubeBe = pairMatches(hostParts[0], hostParts[1], youtuBe)
        case 3:
            let sub = hostParts[0]
            isYouTubeHost = isValidSubdomainLabel(sub)
                && (pairMatches(hostParts[1], hostParts[2], youtubeCom) || pairMatches(hostParts[1], hostParts[2], noCookie))
            isYouTubeBe = isValidSubdomainLabel(sub) && pairMatches(hostParts[1], hostParts[2], youtuBe)
        default:
            break
        }
        let pathStart = text.index(after: hostEnd)
        if isYouTubeBe {
            if let idEnd = youTubeIDEnd(at: pathStart, in: text) {
                return (String(text[pathStart..<idEnd]), idEnd, search)
            }
            search = text.index(after: search)
            continue
        }
        if isYouTubeHost {
            let rest = text[pathStart...]
            let restLower = rest.lowercased()
            if restLower.hasPrefix("watch") {
                let afterWatch = rest.index(rest.startIndex, offsetBy: 5)
                guard afterWatch < rest.endIndex, rest[afterWatch] == "?" else {
                    search = text.index(after: search)
                    continue
                }
                // v= may sit anywhere in the query; try candidates left-to-right
                // (the regex's non-greedy expansion order).
                let queryStart = rest.index(after: afterWatch)
                var queryEnd = queryStart
                while queryEnd < rest.endIndex, rest[queryEnd] != "#", !rest[queryEnd].isWhitespace {
                    queryEnd = rest.index(after: queryEnd)
                }
                if let found = firstWatchID(in: rest[queryStart..<queryEnd]) {
                    return (found.id, found.end, search)
                }
                search = text.index(after: search)
                continue
            }
            for prefix in ["shorts/", "live/", "embed/"] where restLower.hasPrefix(prefix) {
                let idStart = rest.index(rest.startIndex, offsetBy: prefix.count)
                if let idEnd = youTubeIDEnd(at: idStart, in: rest) {
                    return (String(rest[idStart..<idEnd]), idEnd, search)
                }
            }
            search = text.index(after: search)
            continue
        }
        search = text.index(after: search)
    }
    return nil
}

/// Finds the first `v=` whose following 11 characters form an ID with a valid tail
/// guard — left-to-right, matching the regex's non-greedy expansion order.
private func firstWatchID(in query: Substring) -> (id: String, end: Substring.Index)? {
    var search = query.startIndex
    while search < query.endIndex {
        guard let v = query[search...].range(of: "v=", options: .caseInsensitive) else { return nil }
        let idStart = v.upperBound
        if let idEnd = youTubeIDEnd(at: idStart, in: query) {
            return (String(query[idStart..<idEnd]), idEnd)
        }
        search = query.index(after: v.lowerBound)
    }
    return nil
}

/// `findYouTubeUrls` (youtube/urls.ts): exact source ranges for in-prose YouTube URLs.
func youtubeHits(in text: Substring) -> [YouTubeURLHit] {
    var hits: [YouTubeURLHit] = []
    var search = text.startIndex
    while search < text.endIndex {
        guard let match = parseYouTubeMatch(in: text, from: search) else { break }
        var end = match.idEnd
        while end < text.endIndex && isYouTubeURLChar(text[end]) {
            end = text.index(after: end)
        }
        let trimEnd = trailingPunctuationEnd(match.matchStart..<end, in: text, stoppingAt: youTubeTrailingPunctuation)
        hits.append(YouTubeURLHit(url: String(text[match.matchStart..<trimEnd]), id: match.id, range: match.matchStart..<trimEnd))
        search = trimEnd
    }
    return hits
}



// MARK: - Paragraph model (§1.1 cards, §1.2 placement)

private struct ParagraphBlock {
    var lines: [Range<String.Index>]
    var inList: Bool
    /// True when the block is a setext heading (its last line is `===` or `---`).
    var setextHeading: Bool
}

/// Trim leading/trailing whitespace, keeping absolute indices.
private func trimmedSlice<S: StringProtocol>(_ range: Range<S.Index>, in text: S) -> (text: S.SubSequence, range: Range<S.Index>) {
    var start = range.lowerBound
    var end = range.upperBound
    while start < end && text[start].isWhitespace { start = text.index(after: start) }
    while end > start && text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
    return (text[start..<end], start..<end)
}

/// Strips leading blockquote markers (`{0,3}>[ \t]?` repeated), keeping indices.
private func stripBlockquote<S: StringProtocol>(_ range: Range<S.Index>, in text: S) -> Range<S.Index> {
    var current = range
    while true {
        let rest = text[current]
        var i = rest.startIndex
        var indent = 0
        while i < rest.endIndex && rest[i] == " " && indent < 3 {
            indent += 1
            i = rest.index(after: i)
        }
        guard i < rest.endIndex, rest[i] == ">" else { break }
        i = rest.index(after: i)
        if i < rest.endIndex && (rest[i] == " " || rest[i] == "\t") {
            i = rest.index(after: i)
        }
        current = i..<current.upperBound
    }
    return current
}

private func isBlankSlice<S: StringProtocol>(_ slice: S) -> Bool {
    slice.allSatisfy { $0.isWhitespace }
}

private func isATXHeading<S: StringProtocol>(_ slice: S) -> Bool {
    var i = slice.startIndex
    var indent = 0
    while i < slice.endIndex && slice[i] == " " && indent < 3 {
        indent += 1
        i = slice.index(after: i)
    }
    if indent > 3 { return false }
    var hashes = 0
    while i < slice.endIndex && slice[i] == "#" && hashes < 7 {
        hashes += 1
        i = slice.index(after: i)
    }
    guard (1...6).contains(hashes) else { return false }
    return i == slice.endIndex || slice[i].isWhitespace
}

/// `^ {0,3}\[[^\]]*\]:` — a link reference definition: invisible to the renderer,
/// and a block boundary. (Inline reference links `[a][b]` are non-text for §1.1.)
private func isLinkDefinition<S: StringProtocol>(_ slice: S) -> Bool {
    var i = slice.startIndex
    var indent = 0
    while i < slice.endIndex && slice[i] == " " && indent < 3 {
        indent += 1
        i = slice.index(after: i)
    }
    if indent > 3 { return false }
    guard i < slice.endIndex, slice[i] == "[" else { return false }
    i = slice.index(after: i)
    while i < slice.endIndex {
        if slice[i] == "]" {
            i = slice.index(after: i)
            return i < slice.endIndex && slice[i] == ":"
        }
        if slice[i] == "[" || slice[i] == "\n" { return false }
        i = slice.index(after: i)
    }
    return false
}

/// Thematic break: all non-space chars the same from `-*_`, at least 3 (`* * *`,
/// `---`, `___`). Interrupts a paragraph but never makes it a heading.
private func isThematicBreak<S: StringProtocol>(_ slice: S) -> Bool {
    let trimmed = slice.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 3, let first = trimmed.first, "-*_".contains(first) else {
        return false
    }
    return trimmed.allSatisfy { $0 == first || $0.isWhitespace }
}

/// Setext underline: one or more unbroken `=` (H1) or `-` (H2). A setext underline
/// *after content* makes the open block a heading in mdast — nothing inside it hosts
/// rich content. Otherwise it is an H2 thematic break.
private func isSetextUnderline<S: StringProtocol>(_ slice: S) -> Bool {
    let trimmed = slice.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first, first == "=" || first == "-" else { return false }
    return !trimmed.isEmpty && trimmed.allSatisfy { $0 == first }
}

private func isListItem<S: StringProtocol>(_ slice: S) -> Bool {
    var i = slice.startIndex
    var indent = 0
    while i < slice.endIndex && slice[i] == " " && indent < 3 {
        indent += 1
        i = slice.index(after: i)
    }
    if indent > 3 { return false }
    guard i < slice.endIndex else { return false }
    let marker = slice[i]
    if marker == "-" || marker == "*" || marker == "+" {
        i = slice.index(after: i)
        return i == slice.endIndex || slice[i].isWhitespace
    }
    // `1.` / `1)` — up to 9 digits.
    var digits = 0
    var j = i
    while j < slice.endIndex && slice[j].isNumber && digits < 9 {
        digits += 1
        j = slice.index(after: j)
    }
    if digits > 0 && j < slice.endIndex && (slice[j] == "." || slice[j] == ")") {
        j = slice.index(after: j)
        return j == slice.endIndex || slice[j].isWhitespace
    }
    return false
}

/// Leading spaces (a tab counts as four) — used to tell an indented list
/// continuation from a new top-level block.
private func leadingIndent<S: StringProtocol>(_ text: S) -> Int {
    var indent = 0
    for char in text {
        if char == " " {
            indent += 1
        } else if char == "\t" {
            indent += 4
        } else {
            break
        }
    }
    return indent
}

/// True when a line starts a new block rather than continuing a paragraph. Keeps a
/// lazy paragraph continuation of a list item from ending the list early.
private func isParagraphBlockStarter<S: StringProtocol>(_ line: S) -> Bool {
    var i = line.startIndex
    var indent = 0
    while i < line.endIndex && line[i] == " " && indent < 4 {
        indent += 1
        i = line.index(after: i)
    }
    if indent >= 4 { return true } // indented code block
    guard i < line.endIndex else { return false }
    let marker = line[i]
    if marker == ">" || marker == "#" || marker == "<" { return true }
    let rest = line[i...]
    if isListItem(rest) || isThematicBreak(rest) || isSetextUnderline(rest) { return true }
    return openingFence(rest) != nil
}

/// `<svg` at the start of a line, opening a tag (not a self-closing `<svg/>`).
private func opensSVG<S: StringProtocol>(_ line: S) -> Bool {
    let trimmed = line.drop(while: { $0.isWhitespace })
    guard let range = trimmed.range(of: "<svg", options: .caseInsensitive) else { return false }
    guard range.lowerBound == trimmed.startIndex else { return false }
    let after = trimmed[range.upperBound...]
    guard let first = after.first else { return true } // the tag continues on the next line
    return first.isWhitespace || first == ">"
}

private func closesSVG<S: StringProtocol>(_ line: S) -> Bool {
    line.range(of: "</svg", options: .caseInsensitive) != nil
}

private func isBareURLLine(_ t: Substring) -> Bool {
    let lower = t.lowercased()
    guard (lower.hasPrefix("http://") || lower.hasPrefix("https://")) else { return false }
    return !t.contains(where: { $0.isWhitespace })
}

/// §1.2 — `isStandaloneYouTubeLine`: the whole trimmed line is one YouTube URL
/// or bare ID (never a substring).
private func isStandaloneYouTubeLine(_ t: Substring) -> Bool {
    guard !t.isEmpty else { return false }
    if isBareYouTubeID(t) { return true }
    guard isBareURLLine(t) else { return false }
    return RichContentDetector.youtubeID(for: String(t)) != nil
}

/// §1.1/§1.2 — paragraph-aware cards and players. `outside` excludes fenced code
/// from the line model (fences are block separators); `purityExclusions` (code
/// spans, raw SVG, authored links/autolinks) decides whether a block is "all text";
/// authored links stay visible and drive the mixed-block inline players.
func paragraphBlocks(
    in source: String,
    outside excluded: [Range<String.Index>],
    purityExclusions: [Range<String.Index>],
    linkSpans: [LinkSpan]
) -> [RichContentBlock] {
    var out: [RichContentBlock] = []
    for region in unprotectedSegments(source, excluding: excluded) {
        var blocks: [ParagraphBlock] = []
        var open: [Range<String.Index>] = []
        var openInList = false

        func close(setext: Bool) {
            if !open.isEmpty {
                blocks.append(ParagraphBlock(lines: open, inList: openInList, setextHeading: setext))
                open = []
                openInList = false
            }
        }

        for rawRange in splitRegion(region) {
            let stripped = stripBlockquote(rawRange, in: source)
            let slice = source[stripped]
            if isSetextUnderline(slice) {
                close(setext: !open.isEmpty) // setext vetoes the open block; alone it is an hr
                continue
            }
            if isThematicBreak(slice) {
                close(setext: false) // an hr interrupts a paragraph but never vetoes it
                continue
            }
            if isBlankSlice(slice) || isATXHeading(slice) || isLinkDefinition(slice) {
                close(setext: false)
                continue
            }
            let listStart = isListItem(slice)
            if open.isEmpty { openInList = listStart }
            open.append(stripped)
        }
        if !open.isEmpty {
            blocks.append(ParagraphBlock(lines: open, inList: openInList, setextHeading: false))
        }

        for block in blocks {
            out.append(contentsOf: emitParagraph(block, source: source, purityExclusions: purityExclusions, linkSpans: linkSpans))
        }
    }
    return out
}

/// Line records keep absolute indices (all substrings in this module index into
/// the original source). Splits a region on newlines.
/// Line records keep absolute indices (all substrings in this module index into
/// the original source). Splits a region on LF, CRLF or CR.
private func splitRegion(_ region: Substring) -> [Range<String.Index>] {
    var lines: [Range<String.Index>] = []
    var start = region.startIndex
    var i = region.startIndex
    while i < region.endIndex {
        if region[i] == "\n" || region[i] == "\r\n" || region[i] == "\r" {
            lines.append(start..<i)
            i = region.index(after: i)
            start = i
        } else {
            i = region.index(after: i)
        }
    }
    if start < region.endIndex { lines.append(start..<region.endIndex) }
    return lines
}

private func emitParagraph(
    _ block: ParagraphBlock,
    source: String,
    purityExclusions: [Range<String.Index>],
    linkSpans: [LinkSpan]
) -> [RichContentBlock] {
    guard let first = block.lines.first, let last = block.lines.last else { return [] }
    let blockRange = first.lowerBound..<last.upperBound

    // §1.1/§1.2 — a setext block is a heading in mdast: no paragraph at all, so no
    // cards and no players. (Its lines were already added to the block.)
    if block.setextHeading { return [] }

    // Sole authored link (§1.2): exactly one non-image link in the block and
    // everything else is whitespace → one full player spanning the block.
    let inBlock = linkSpans.filter { $0.range.lowerBound >= blockRange.lowerBound && $0.range.upperBound <= blockRange.upperBound }
    if inBlock.count == 1, let link = inBlock.first, !link.isImage,
       let url = link.url, let id = RichContentDetector.youtubeID(for: url) {
        var cursor = blockRange.lowerBound
        var allWhitespace = true
        while cursor < blockRange.upperBound {
            if cursor == link.range.lowerBound {
                cursor = link.range.upperBound
                continue
            }
            if !source[cursor].isWhitespace {
                allWhitespace = false
                break
            }
            cursor = source.index(after: cursor)
        }
        if allWhitespace {
            return [.youTubePlayer(YouTubeReference(id: id, url: url), range: blockRange)]
        }
    }

    // §1.1 — a block is "all text" (card/standalone-player eligible) iff it overlaps
    // no purity exclusion (code spans, raw SVG, authored links/autolinks) and carries
    // no reference-style link markup (`[a][b]`).
    var allText = !block.lines.contains { overlapsAny($0, in: purityExclusions) }
    if allText {
        for line in block.lines {
            if source[line].range(of: "][") != nil {
                allText = false
                break
            }
        }
    }

    if allText {
        var out: [RichContentBlock] = []
        // §1.1 — cards (list items and headings veto cards; blockquotes do not).
        if !block.inList {
            for line in block.lines {
                let (trimmed, trimmedRange) = trimmedSlice(line, in: source)
                let text = String(trimmed)
                // M17 — a standalone map reference hosts a map card instead of a link card.
                if let map = RichContentDetector.mapReference(forLine: text) {
                    out.append(.mapCard(map, range: trimmedRange))
                    continue
                }
                guard isBareURLLine(trimmed),
                      !RichContentDetector.isRemoteImageURL(text),
                      RichContentDetector.youtubeID(for: text) == nil else { continue }
                out.append(.linkCard(url: text, range: trimmedRange))
            }
        }
        // §1.2 — pure-text paragraphs: standalone line ⇒ full player, anything else
        // is scanned in place for the prose player.
        for line in block.lines {
            let (trimmed, trimmedRange) = trimmedSlice(line, in: source)
            if isStandaloneYouTubeLine(trimmed), let id = RichContentDetector.youtubeID(for: String(trimmed)) {
                out.append(.youTubePlayer(YouTubeReference(id: id, url: String(trimmed)), range: trimmedRange))
                continue
            }
            for hit in youtubeHits(in: source[line]) {
                out.append(.youTubeInline(YouTubeReference(id: hit.id, url: hit.url), range: hit.range))
            }
        }
        return out
    }

    // §1.2 — mixed blocks: an authored link with a YouTube URL hosts an inline
    // player spanning the link; text pieces (excluding code spans, raw SVG and
    // other authored links) are scanned in place.
    let exclusions = mergeRanges(purityExclusions)
    var out: [RichContentBlock] = []
    for line in block.lines {
        let lineExclusions = exclusions.filter { $0.lowerBound < line.upperBound && $0.upperBound > line.lowerBound }
        // Text pieces between excluded spans.
        var pieces: [Range<String.Index>] = []
        var cursor = line.lowerBound
        for span in lineExclusions {
            if cursor < span.lowerBound { pieces.append(cursor..<span.lowerBound) }
            cursor = max(cursor, span.upperBound)
        }
        if cursor < line.upperBound { pieces.append(cursor..<line.upperBound) }
        for piece in pieces {
            for hit in youtubeHits(in: source[piece]) {
                out.append(.youTubeInline(YouTubeReference(id: hit.id, url: hit.url), range: hit.range))
            }
        }
        let lineLinks = inBlock.filter { $0.range.lowerBound >= line.lowerBound && $0.range.upperBound <= line.upperBound }
        for link in lineLinks where !link.isImage {
            if let url = link.url, let id = RichContentDetector.youtubeID(for: url) {
                out.append(.youTubeInline(YouTubeReference(id: id, url: url), range: link.range))
            }
        }
    }
    return out
}
