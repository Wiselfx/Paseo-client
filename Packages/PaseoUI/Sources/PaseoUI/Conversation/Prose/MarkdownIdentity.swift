#if canImport(UIKit)
import Foundation

extension Array {
    /// Wraps each value with a stable `ForEach` identity (P5-B).
    ///
    /// Settled values are identified by their own content (hashed, plus their occurrence among
    /// identical values), so inserting or removing one does not shift the identity of the values
    /// after it — the offset ids used before did. The open (last) value is identified by position
    /// instead: its text streams in, so a content hash would change on every token and SwiftUI
    /// would tear the view down and rebuild it, losing its internal state (e.g. a code block's
    /// scroll offset). Its position is stable while it grows.
    func identifiedValues(hashing: (Element) -> Int) -> [MarkdownIdentifiedValue<Element>] {
        var occurrences: [Int: Int] = [:]
        let lastIndex = count - 1
        return enumerated().map { index, value in
            if index == lastIndex {
                return MarkdownIdentifiedValue(
                    id: MarkdownStableID(open: true, value: index, occurrence: 0), index: index, value: value)
            }
            let contentHash = hashing(value)
            let occurrence = occurrences[contentHash, default: 0]
            occurrences[contentHash] = occurrence + 1
            return MarkdownIdentifiedValue(
                id: MarkdownStableID(open: false, value: contentHash, occurrence: occurrence), index: index,
                value: value)
        }
    }
}

extension Array where Element == MarkdownBlock {
    /// Blocks with their stable identities; see `identifiedValues(hashing:)`.
    func identifiedBlocks() -> [MarkdownIdentifiedValue<MarkdownBlock>] {
        identifiedValues { block in
            var hasher = Hasher()
            block.hashStable(into: &hasher)
            return hasher.finalize()
        }
    }
}

extension Array where Element == MarkdownListItem {
    /// List items get the same treatment; the ordered-list number needs the index.
    func identifiedItems() -> [MarkdownIdentifiedValue<MarkdownListItem>] {
        identifiedValues { item in
            var hasher = Hasher()
            item.hashStable(into: &hasher)
            return hasher.finalize()
        }
    }
}

extension Array where Element == [[MarkdownInline]] {
    /// Table rows, identified by their own cells.
    func identifiedRows() -> [MarkdownIdentifiedValue<[[MarkdownInline]]>] {
        identifiedValues { row in
            var hasher = Hasher()
            for cell in row { cell.hashStable(into: &hasher) }
            return hasher.finalize()
        }
    }
}
#endif
