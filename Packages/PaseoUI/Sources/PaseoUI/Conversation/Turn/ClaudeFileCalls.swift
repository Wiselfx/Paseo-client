#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// What the rows inside a work group stand for, after merging consecutive same-file calls.
/// Internal to the transcript: the merged row is still one logical tool call to the transcript
/// (one expand/collapse, one line), it just fans out to several calls in the expanded body.
enum WorkRow: Identifiable, Hashable {
    /// A thought row (reasoning).
    case thought(TimelineRow)
    /// Any non-file tool call.
    case tool(TimelineRow)
    /// A merged run of consecutive read/edit/write calls on the same file.
    case fileCall(ClaudeMergedFileCall)

    var id: String {
        switch self {
        case .thought(let row): row.id
        case .tool(let row): row.id
        case .fileCall(let call): call.id
        }
    }

    /// Ordered by the first row's position.
    static func merging(_ rows: [TimelineRow]) -> [WorkRow] {
        var output: [WorkRow] = []
        var pending: ClaudeMergedFileCall?

        func flushPending() {
            guard let call = pending else { return }
            output.append(.fileCall(call))
            pending = nil
        }

        for row in rows {
            guard case .toolCall(let call) = row.item else {
                flushPending()
                output.append(.thought(row))
                continue
            }
            guard let path = Self.filePath(of: call), let kind = Self.fileKind(of: call) else {
                flushPending()
                output.append(.tool(row))
                continue
            }
            if var open = pending, open.path == path, open.kind == kind {
                open.append(call, seqEnd: row.seqEnd)
                pending = open
            } else {
                flushPending()
                pending = ClaudeMergedFileCall(
                    kind: kind, path: path, firstRowId: row.id, calls: [call], rowSeqEnds: [row.seqEnd])
            }
        }
        flushPending()
        return output
    }

    private static func filePath(of call: ToolCall) -> String? {
        switch call.detail {
        case .read(let path, _), .edit(let path, _, _, _), .write(let path, _): return path
        default: return nil
        }
    }

    private static func fileKind(of call: ToolCall) -> ClaudeMergedFileCall.Kind? {
        switch call.detail {
        case .read: return .read
        case .edit: return .edit
        case .write: return .write
        default: return nil
        }
    }
}

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

    /// The cached per-call parse. `NSCache` drops entries under memory pressure.
    @MainActor private static let diffStatCache = NSCache<NSString, DiffStatBox>()

    @MainActor
    private static func diffStat(of call: ToolCall) -> (added: Int, removed: Int)? {
        guard case .edit(_, let oldString, let newString, let unifiedDiff) = call.detail else { return nil }
        let key: NSString
        if let diff = unifiedDiff, !diff.isEmpty {
            key = "diff:\(diff.hashValue):\(diff.count)" as NSString
        } else {
            let old = oldString ?? ""
            let new = newString ?? ""
            key = "pair:\(old.hashValue):\(old.count):\(new.hashValue):\(new.count)" as NSString
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

/// A boxed diff stat; `NSCache` only holds class values.
private final class DiffStatBox {
    let added: Int
    let removed: Int

    init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }
}

#endif
