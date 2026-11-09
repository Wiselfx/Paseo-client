#if canImport(UIKit)
import Foundation
import PaseoStore

/// One piece of assistant prose in document order: a chunk of Markdown, or a rich-content
/// block detected by `RichContentDetector`.
enum RichPiece {
    case markdown(String)
    case block(RichContentBlock)
}

/// Small in-memory memo for `RichContentDetector.detect(in:)`. The prose re-renders on
/// every streamed delta, so detection would run once per token; it is pure and
/// deterministic, hence cacheable. Evict-all when the table fills. Called from view
/// bodies, i.e. on the main actor.
@MainActor
enum RichContentCache {
    private static var table: [String: [RichContentBlock]] = [:]

    static func detect(_ source: String) -> [RichContentBlock] {
        if let cached = table[source] { return cached }
        let blocks = RichContentDetector.detect(in: source)
        if table.count >= 64 { table.removeAll(keepingCapacity: true) }
        table[source] = blocks
        return blocks
    }
}

/// Splits `source` into the Markdown chunks between rich-content blocks and the blocks
/// themselves, in document order. Markdown chunks are passed through untouched; rich
/// blocks are emitted whole.
@MainActor
func richPieces(_ source: String) -> [RichPiece] {
    let blocks = RichContentCache.detect(source)
    guard !blocks.isEmpty else { return [.markdown(source)] }
    var pieces: [RichPiece] = []
    var cursor = source.startIndex
    for block in blocks {
        let range = block.range
        if cursor < range.lowerBound {
            pieces.append(.markdown(String(source[cursor..<range.lowerBound])))
        }
        pieces.append(.block(block))
        cursor = range.upperBound
    }
    if cursor < source.endIndex {
        pieces.append(.markdown(String(source[cursor...])))
    }
    return pieces
}
#endif
