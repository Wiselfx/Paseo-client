import Foundation
import Markdown
import PaseoStore

/// Small in-memory memo for the prose parse (P3), now an LRU under a byte budget
/// (P5-B): the previous table evicted wholesale at 64 entries, so scrolling back to an
/// earlier message re-parsed it. Keys share storage with the strings the views hold.
enum MarkdownDocumentCache {
    private struct Key: Hashable {
        let source: String
        let home: String?
    }

    private static let table = ProseCache<Key, MarkdownDocumentModel>(
        budget: 4 * 1024 * 1024,
        countLimit: 512,
        cost: { key, _ in key.source.utf8.count * 4 })

    static func document(for source: String, home: String? = nil, store: Bool = true) -> MarkdownDocumentModel {
        let key = Key(source: source, home: home?.isEmpty == true ? nil : home)
        if let cached = table.value(for: key) { return cached }
        PaseoPerf.count("md.miss")
        let document = PaseoPerf.measure("md.parse") {
            MarkdownDocumentModel(source: source, home: key.home)
        }
        if store { table.setValue(document, for: key) }
        return document
    }
}
