#if canImport(UIKit)
import Foundation
import PaseoStore

/// One piece of assistant prose in document order: a chunk of Markdown, or a rich-content
/// block detected by `RichContentDetector`.
enum RichPiece {
    case markdown(String)
    /// The block plus its UTF-16 length in the unit it was detected from (the unit is
    /// linkified, so its ranges do not index the original source).
    case block(RichContentBlock, utf16Length: Int)
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
@MainActor
func richPieces(_ source: String) -> [RichPiece] {
    var pieces: [RichPiece] = []
    // Adjacent single-image units whose only separation is blank text merge into one
    // gallery block (G7 C2). The decision is the pure `RichImageGrouping` rule; this
    // loop only tracks unit ranges and buffers one unit's normal splice, so a lone
    // image re-emits exactly what the old code produced.
    var pendingImages: [RichImage] = []
    var pendingRange: Range<String.Index>?
    var pendingPieces: [RichPiece] = []
    var previousUnitEnd: String.Index? = nil

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

    func flushPending() {
        if pendingImages.count >= 2, let range = pendingRange {
            let length = source[range].utf16.count
            pieces.append(.block(
                RichImageGrouping.group(images: pendingImages, range: range), utf16Length: length))
        } else {
            pieces.append(contentsOf: pendingPieces)
        }
        pendingImages = []
        pendingRange = nil
        pendingPieces = []
    }

    for range in RichContentDetector.splitIntoBlocks(source) {
        let unit = String(source[range])
        let linked = FilePathLinks.linkifiedForProse(unit)
        let blocks = RichContentCache.detect(linked)
        guard !blocks.isEmpty else {
            flushPending()
            previousUnitEnd = range.upperBound
            pieces.append(.markdown(linked))
            continue
        }
        // A sole-image unit: exactly one image block and no visible markdown.
        let soleImage: RichImage? = {
            guard blocks.count == 1, let image = RichImage.of(block: blocks[0]) else { return nil }
            let markdown = linkedWithoutBlocks(linked, blocks: blocks)
            guard markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return image
        }()
        if let soleImage {
            let gapBlank: Bool = {
                guard let previousUnitEnd else { return true }
                return source[previousUnitEnd..<range.lowerBound].allSatisfy(\.isWhitespace)
            }()
            if gapBlank {
                if let pending = pendingRange {
                    pendingRange = pending.lowerBound..<range.upperBound
                } else {
                    pendingRange = range
                }
                pendingImages.append(soleImage)
                pendingPieces = spliceUnit(linked: linked, blocks: blocks)
                previousUnitEnd = range.upperBound
                continue
            }
        }
        flushPending()
        previousUnitEnd = range.upperBound
        pieces.append(contentsOf: spliceUnit(linked: linked, blocks: blocks))
    }
    flushPending()
    return pieces
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
