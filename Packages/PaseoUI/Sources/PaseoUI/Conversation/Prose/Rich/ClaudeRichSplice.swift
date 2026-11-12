#if canImport(UIKit)
import Foundation
import PaseoStore

/// One piece of assistant prose in document order: a chunk of Markdown, a rich-content
/// block detected by `RichContentDetector`, or a standalone file line (G10).
enum RichPiece {
    case markdown(String)
    /// The block plus its UTF-16 length in the unit it was detected from (the unit is
    /// linkified, so its ranges do not index the original source).
    case block(RichContentBlock, utf16Length: Int)
    /// A bare non-image path standing alone on its line: a file card, not a chip.
    /// Detected from the raw unit (the detector sees linkified text and stays out).
    case file(path: String, utf16Length: Int)
}

/// Small in-memory memo for `RichContentDetector.detect(in:)`. The prose re-renders on
/// every streamed delta, so detection would run once per token; it is pure and
/// deterministic, hence cacheable. An LRU under a byte budget (P5-B) keeps the recent
/// units warm instead of evicting the whole table at 64 entries. Called from view
/// bodies, i.e. on the main actor.
@MainActor
enum RichContentCache {
    private static let table = ProseCache<String, [RichContentBlock]>(
        budget: 4 * 1024 * 1024,
        countLimit: 512,
        cost: { source, _ in source.utf8.count })

    static func detect(_ source: String) -> [RichContentBlock] {
        if let cached = table.value(for: source) { return cached }
        let blocks = RichContentDetector.detect(in: source)
        table.setValue(blocks, for: source)
        return blocks
    }
}

extension RichContentBlock {
    /// The card family's stable kind key (G1 §1.4): with the block's start offset it identifies
    /// a card across streaming re-renders, so a newly detected block never re-runs an older
    /// card's entrance. The range itself is the position; this is the kind.
    var cardKindKey: String {
        switch self {
        case .linkCard: "link"
        case .youTubePlayer: "youtube"
        case .youTubeInline: "youtube-inline"
        case .bareImageURL: "image"
        case .localImage: "local-image"
        case .localFileLink: "file"
        case .rawSVG: "svg"
        case .visualize: "visualize"
        case .mermaid: "mermaid"
        case .imageGroup: "gallery"
        case .localMedia(_, let kind, _): kind == .video ? "video" : "audio"
        case .remoteMedia(_, let kind, _): kind == .video ? "video" : "audio"
        case .mapCard: "map"
        }
    }
}

/// Splits `source` into the Markdown chunks between rich-content blocks and the blocks
/// themselves, in document order. The source is first split into block-level units
/// (paragraphs, headings, lists, quotes, fences) by `RichContentDetector.splitIntoBlocks`,
/// so a streamed token only re-parses the open unit; each unit is linkified (M7g) and
/// detected through its own memo. Markdown chunks are otherwise passed through untouched;
/// rich blocks are emitted whole.
///
/// `home` is the agent's working directory (J2): markdown images `![alt](~/a.png)` that
/// sat in a paragraph with anything else now render as images, and text the reader sees
/// gets links for bare URLs (item 3). Nil keeps today's behaviour.
@MainActor
func richPieces(_ source: String, home: String? = nil) -> [RichPiece] {
    var pieces: [RichPiece] = []
    // Adjacent single-image units whose only separation is blank text merge into
    // one gallery block (G7 C2). Standalone files (G10) and playable media (G11)
    // are claimed first, from the raw unit, so linkification cannot hide them.
    // The pending run buffers one unit so a lone image re-emits exactly what the
    // old code produced.
    var pendingImages: [RichImage] = []
    var pendingRange: Range<String.Index>? = nil
    var previousUnitEnd: String.Index? = nil

    /// One image as the block the old code would have emitted for its unit.
    func singleImageBlock(_ image: RichImage, range: Range<String.Index>) -> RichPiece {
        let length = source[range].utf16.count
        switch image.source {
        case .remote(let url):
            return .block(.bareImageURL(url: url, range: range), utf16Length: length)
        case .local(let path):
            return .block(
                .localImage(path: path, alt: image.alt, range: range), utf16Length: length)
        }
    }

    func flushPending() {
        if pendingImages.count >= 2, let range = pendingRange {
            let length = source[range].utf16.count
            pieces.append(.block(
                RichImageGrouping.group(images: pendingImages, range: range), utf16Length: length))
        } else if let first = pendingImages.first, let range = pendingRange {
            pieces.append(singleImageBlock(first, range: range))
        }
        pendingImages = []
        pendingRange = nil
    }

    func gapIsBlank(to upperBound: String.Index) -> Bool {
        guard let previousUnitEnd else { return true }
        return source[previousUnitEnd..<upperBound].allSatisfy(\.isWhitespace)
    }

    func spliceUnit(linked: String, blocks: [RichContentBlock]) -> [RichPiece] {
        var out: [RichPiece] = []
        var cursor = linked.startIndex
        for block in blocks {
            let blockRange = block.range
            if cursor < blockRange.lowerBound {
                out.append(.markdown(String(linked[cursor..<blockRange.lowerBound])))
            }
            let length = linked.utf16.distance(from: blockRange.lowerBound, to: blockRange.upperBound)
            out.append(.block(block, utf16Length: length))
            cursor = blockRange.upperBound
        }
        if cursor < linked.endIndex {
            out.append(.markdown(String(linked[cursor...])))
        }
        return out
    }

    for range in RichContentDetector.splitIntoBlocks(source) {
        let unit = String(source[range])
        // J2 §1: several images in one paragraph are a gallery. Checked before the
        // single-image rules below, from the raw unit (linkification would wrap them).
        if let images = RichImageGrouping.imagesOnly(unit: unit, home: home) {
            let unitRange = range
            if images.count >= 2 {
                flushPending()
                previousUnitEnd = range.upperBound
                pieces.append(.block(
                    RichImageGrouping.group(images: images, range: unitRange),
                    utf16Length: unit.utf16.count))
                continue
            }
            if let image = images.first, gapIsBlank(to: range.lowerBound) {
                if let pending = pendingRange {
                    pendingRange = pending.lowerBound..<range.upperBound
                } else {
                    pendingRange = range
                }
                pendingImages.append(image)
                previousUnitEnd = range.upperBound
                continue
            }
            flushPending()
            previousUnitEnd = range.upperBound
            pieces.append(singleImageBlock(images[0], range: unitRange))
            continue
        }
        // J2 §2: every line is a file — a bare path or an authored link to one — so the
        // unit becomes one card per file rather than a run of blue links.
        if let paths = RichStandaloneFile.linkLines(unit: unit, home: home) {
            flushPending()
            previousUnitEnd = range.upperBound
            pieces.append(contentsOf: fileLinePieces(paths, range: range, unit: unit))
            continue
        }
        // Playable media first (G11): a standalone path or bare URL with a playable
        // extension becomes a player card.
        if let media = RichStandaloneMedia.match(
            blocks: RichContentCache.detect(unit), unitText: unit)
        {
            flushPending()
            previousUnitEnd = range.upperBound
            switch media {
            case .local(let path, let kind):
                pieces.append(.block(
                    .localMedia(path: path, kind: kind, range: range),
                    utf16Length: unit.utf16.count))
            case .remote(let url, let kind):
                pieces.append(.block(
                    .remoteMedia(url: url, kind: kind, range: range),
                    utf16Length: unit.utf16.count))
            }
            continue
        }
        // A bare non-image path standing alone on its line is a file card (G10),
        // decided from the raw unit so linkification cannot hide it.
        if let filePath = RichStandaloneFile.path(
            in: RichContentCache.detect(unit), unitText: unit)
        {
            flushPending()
            previousUnitEnd = range.upperBound
            pieces.append(.file(path: filePath, utf16Length: unit.utf16.count))
            continue
        }
        let linked = FilePathLinks.linkifiedForProse(unit)
        let blocks = RichContentCache.detect(linked)
        // A sole image unit joins the gallery run when only blank text separates it
        // from the previous one (G7). Remote images arrive as blocks here; a sole
        // *local* image is detected from the raw unit, since linkification wraps it
        // into an authored link the detector then skips.
        let soleRemote: RichImage? = {
            guard blocks.count == 1, let image = RichImage.of(block: blocks[0]) else {
                return nil
            }
            let markdown = linkedWithoutBlocks(linked, blocks: blocks)
            guard markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return image
        }()
        let soleLocal: RichImage? = {
            guard soleRemote == nil else { return nil }
            let detected = RichContentCache.detect(unit)
            guard detected.count == 1,
                case .localImage(let path, let alt, _) = detected[0],
                unit.trimmingCharacters(in: .whitespacesAndNewlines) == path
            else { return nil }
            return RichImage(source: .local(path: path), alt: alt)
        }()
        if let soleImage = soleRemote ?? soleLocal, gapIsBlank(to: range.lowerBound) {
            if let pending = pendingRange {
                pendingRange = pending.lowerBound..<range.upperBound
            } else {
                pendingRange = range
            }
            pendingImages.append(soleImage)
            previousUnitEnd = range.upperBound
            continue
        }
        flushPending()
        previousUnitEnd = range.upperBound
        // J2 §4: a list unit is never cut apart. The detector reports the YouTube player
        // inside a list item at the URL's range; splicing the unit at that range removed
        // the item's text and split the list in two. The whole unit renders as markdown —
        // the URL is a link now (§3) — and the players follow it, in order.
        if RichStandaloneFile.isListUnit(unit) {
            let inlinePlayers = blocks.filter {
                if case .youTubeInline = $0 { return true } else { return false }
            }
            if !inlinePlayers.isEmpty {
                pieces.append(.markdown(unit))
                for block in inlinePlayers {
                    let blockRange = block.range
                    pieces.append(.block(
                        block,
                        utf16Length: linked.utf16.distance(
                            from: blockRange.lowerBound, to: blockRange.upperBound)))
                }
                continue
            }
        }
        if blocks.isEmpty {
            pieces.append(.markdown(linked))
        } else {
            pieces.append(contentsOf: spliceUnit(linked: linked, blocks: blocks))
        }
    }
    flushPending()
    return pieces
}

/// J2 §2: one piece per file path, in order. The UTF-16 lengths sum to the unit's length
/// (the reveal animation walks the pieces by length) — split by line, and the remainder
/// rides the last piece, which keeps the sum exact even when a line's stored text is
/// longer than its path (an authored `[name](path)`).
@MainActor
private func fileLinePieces(
    _ paths: [String], range: Range<String.Index>, unit: String
) -> [RichPiece] {
    let unitLength = unit.utf16.count
    let lineLengths = unitLineLengths(unit)
    var pieces: [RichPiece] = []
    var used = 0
    for (index, path) in paths.enumerated() {
        let isLast = index == paths.count - 1
        let length: Int
        if isLast {
            length = max(0, unitLength - used)
        } else {
            length = lineLengths.indices.contains(index) ? lineLengths[index] : 0
        }
        used += length
        if let kind = RichStandaloneMedia.kindForPath(path) {
            pieces.append(.block(.localMedia(path: path, kind: kind, range: range), utf16Length: length))
        } else if RichContentDetector.isLocalImagePath(path) {
            let alt = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
            pieces.append(.block(.localImage(path: path, alt: alt, range: range), utf16Length: length))
        } else {
            pieces.append(.file(path: path, utf16Length: length))
        }
    }
    return pieces
}

/// The unit's non-blank lines as UTF-16 lengths, each followed by the line's terminator,
/// so consecutive lengths cover the whole unit. Blank lines ride the line before them.
private func unitLineLengths(_ unit: String) -> [Int] {
    var lengths: [Int] = []
    var current = 0
    var lineHasContent = false
    for line in unit.split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline) {
        let content = line.trimmingCharacters(in: .whitespaces)
        if content.isEmpty && !lineHasContent { continue }
        current += line.utf16.count + 1 // + the newline that followed it
        lineHasContent = true
        lengths.append(current)
        current = 0
        lineHasContent = false
    }
    return lengths
}

/// The unit's text with its detected blocks removed: blank means the unit carries no
/// visible prose and a sole image block in it may join a gallery run.
private func linkedWithoutBlocks(_ linked: String, blocks: [RichContentBlock]) -> String {
    var cursor = linked.startIndex
    var out = ""
    for block in blocks {
        let blockRange = block.range
        if cursor < blockRange.lowerBound {
            out += linked[cursor..<blockRange.lowerBound]
        }
        cursor = blockRange.upperBound
    }
    if cursor < linked.endIndex {
        out += linked[cursor...]
    }
    return out
}
#endif
