#if canImport(UIKit)
import Foundation
import PaseoStore

/// The rich-piece split of a whole message, remembered per (source, home) (W1): the views split on every
/// first render of a message and the warm-up splits off the main actor, both through here.
enum RichPiecesCache {
    private struct Key: Hashable {
        let source: String
        let home: String?
    }

    private static let table = ProseCache<Key, [RichPiece]>(
        budget: 8 * 1024 * 1024,
        countLimit: 256,
        cost: { key, _ in key.source.utf8.count * 2 })

    /// `transient`: a streamed message's intermediate text. It is split but never stored: tens of
    /// partial copies a second would push every settled message out of the budget, and scrolling
    /// back would split them all again.
    static func pieces(_ source: String, home: String?, transient: Bool = false) -> [RichPiece] {
        let key = Key(source: source, home: home)
        if let cached = table.value(for: key) { return cached }
        let pieces = richPieces(source, home: home)
        if !transient { table.setValue(pieces, for: key) }
        return pieces
    }
}
#endif
