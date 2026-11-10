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

/// Splits `source` into the Markdown chunks between rich-content blocks and the blocks
/// themselves, in document order. The source is first split into block-level units
/// (paragraphs, headings, lists, quotes, fences) by `RichContentDetector.splitIntoBlocks`,
/// so a streamed token only re-parses the open unit; each unit is linkified (M7g) and
/// detected through its own memo. Markdown chunks are otherwise passed through untouched;
/// rich blocks are emitted whole.
@MainActor
func richPieces(_ source: String) -> [RichPiece] {
    var pieces: [RichPiece] = []
    for range in RichContentDetector.splitIntoBlocks(source) {
        let unit = String(source[range])
        let linked = FilePathLinks.linkifiedForProse(unit)
        let blocks = RichContentCache.detect(linked)
        guard !blocks.isEmpty else {
            pieces.append(.markdown(linked))
            continue
        }
        var cursor = linked.startIndex
        for block in blocks {
            let blockRange = block.range
            if cursor < blockRange.lowerBound {
                pieces.append(.markdown(String(linked[cursor..<blockRange.lowerBound])))
            }
            let length = linked.utf16.distance(from: blockRange.lowerBound, to: blockRange.upperBound)
            pieces.append(.block(block, utf16Length: length))
            cursor = blockRange.upperBound
        }
        if cursor < linked.endIndex {
            pieces.append(.markdown(String(linked[cursor...])))
        }
    }
    return pieces
}
#endif
