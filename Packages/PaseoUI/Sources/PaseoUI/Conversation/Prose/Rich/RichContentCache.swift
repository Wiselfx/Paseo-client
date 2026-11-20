#if canImport(UIKit)
import Foundation
import PaseoStore

/// Small in-memory memo for `RichContentDetector.detect(in:)`. The prose re-renders on
/// every streamed delta, so detection would run once per token; it is pure and
/// deterministic, hence cacheable. An LRU under a byte budget (P5-B) keeps the recent
/// units warm instead of evicting the whole table at 64 entries. Called from view
/// bodies, i.e. on the main actor.
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
#endif
