#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// A run of consecutive read/edit/write calls on the same file, collapsed into one row.
struct ClaudeMergedFileCall: Hashable {
    enum Kind {
        case read, edit, write
    }

    var kind: Kind
    var path: String
    var firstRowId: String
    var calls: [ToolCall]
    /// `seqEnd` of every source row, for the find feature: the merged row expands when a match
    /// lands on any of them, and flashes like the single rows it replaced.
    var rowSeqEnds: [Int]

    var id: String { "file:\(firstRowId)" }

    var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var verb: String {
        switch kind {
        case .read: "Read"
        case .edit: "Edit"
        case .write: "Write"
        }
    }

    var count: Int { calls.count }

    /// Added/removed lines across every call in the run, for the `+N −M` badge. Each call's
    /// parse is cached by the diff string's hash and length, so scrolling never re-splits a diff.
    @MainActor
    var diffStat: (added: Int, removed: Int)? {
        var added = 0, removed = 0, counted = 0
        for call in calls {
            guard case .edit = call.detail, let stat = Self.diffStat(of: call) else { continue }
            added += stat.added
            removed += stat.removed
            counted += 1
        }
        return counted == 0 ? nil : (added, removed)
    }

    mutating func append(_ call: ToolCall, seqEnd: Int) {
        calls.append(call)
        rowSeqEnds.append(seqEnd)
    }

    /// The cached per-call parse. `NSCache` drops entries under memory pressure. Keyed by content
    /// (hash plus UTF-8 length, which is O(1) on native strings, unlike the grapheme `count`).
    @MainActor private static let diffStatCache = NSCache<NSString, DiffStatBox>()

    @MainActor
    private static func diffStat(of call: ToolCall) -> (added: Int, removed: Int)? {
        guard case .edit(_, let oldString, let newString, let unifiedDiff) = call.detail else { return nil }
        let key: NSString
        if let diff = unifiedDiff, !diff.isEmpty {
            key = "diff:\(diff.hashValue):\(diff.utf8.count)" as NSString
        } else {
            let old = oldString ?? ""
            let new = newString ?? ""
            key = "pair:\(old.hashValue):\(old.utf8.count):\(new.hashValue):\(new.utf8.count)" as NSString
        }
        if let hit = diffStatCache.object(forKey: key) { return (hit.added, hit.removed) }
        let stat = computeDiffStat(oldString: oldString, newString: newString, unifiedDiff: unifiedDiff)
        if let stat {
            diffStatCache.setObject(DiffStatBox(added: stat.added, removed: stat.removed), forKey: key)
        }
        return stat
    }

    private static func computeDiffStat(
        oldString: String?, newString: String?, unifiedDiff: String?
    ) -> (added: Int, removed: Int)? {
        if let diff = unifiedDiff, !diff.isEmpty {
            var added = 0, removed = 0
            for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { continue }
                if line.hasPrefix("+") { added += 1 } else if line.hasPrefix("-") { removed += 1 }
            }
            return (added, removed)
        }
        let oldCount = oldString?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        let newCount = newString?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        if oldCount == 0 && newCount == 0 { return nil }
        return (newCount, oldCount)
    }
}
#endif
