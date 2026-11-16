import Foundation
import PaseoProtocol

// MARK: - TurnChangeSummary (G6 C11)

// NOTE: RemoteImagePipeline/G6: the single useful fact about a coding turn — what files
// changed. Built incrementally with the turn (the field lives on `Turn`, so the tail
// rebuild recomputes only rebuilt turns; a test asserts incremental == full rebuild).

/// Per-file line counts for the edit/write tool calls in one turn, in first-touched
/// order. Nil when the turn changed nothing.
public struct TurnChangeSummary: Sendable, Equatable {
    public struct FileChange: Sendable, Equatable, Hashable {
        /// Workspace-relative path, as the tool call reported it.
        public var path: String
        public var added: Int
        public var removed: Int

        public init(path: String, added: Int, removed: Int) {
            self.path = path
            self.added = added
            self.removed = removed
        }
    }

    /// One entry per touched file, in first-touched order.
    public var files: [FileChange]

    public init(files: [FileChange]) {
        self.files = files
    }

    public var fileCount: Int { files.count }
    public var added: Int { files.reduce(0) { $0 + $1.added } }
    public var removed: Int { files.reduce(0) { $0 + $1.removed } }

    /// Summarizes the turn's edit/write tool calls, or nil when there are none. Counts
    /// come from the `unifiedDiff` when present, else from the line counts of
    /// `oldString`/`newString`; a `write` counts as all added. Repeated edits to one
    /// file sum into a single entry.
    public static func summarize(turn: Turn) -> TurnChangeSummary? {
        var files: [FileChange] = []
        var index: [String: Int] = [:]
        for segment in turn.segments {
            guard case .work(let group) = segment else { continue }
            for row in group.rows {
                guard case .toolCall(let call) = row.item else { continue }
                guard let change = counts(for: call.detail) else { continue }
                if let at = index[change.path] {
                    files[at].added += change.added
                    files[at].removed += change.removed
                } else {
                    index[change.path] = files.count
                    files.append(change)
                }
            }
        }
        return files.isEmpty ? nil : TurnChangeSummary(files: files)
    }

    static func counts(for detail: ToolCallDetail) -> FileChange? {
        switch detail {
        case .edit(let path, let oldString, let newString, let unifiedDiff):
            if let unifiedDiff, !(unifiedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let (added, removed) = diffCounts(unifiedDiff)
                return FileChange(path: path, added: added, removed: removed)
            }
            return FileChange(
                path: path, added: lineCount(newString ?? ""),
                removed: lineCount(oldString ?? ""))
        case .write(let path, let content):
            return FileChange(path: path, added: lineCount(content ?? ""), removed: 0)
        default:
            return nil
        }
    }

    /// Added lines start with `+`, removed with `-`, except the `+++`/`---` file
    /// headers. Hunk markers and `\ No newline` notes match neither branch.
    static func diffCounts(_ diff: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                removed += 1
            }
        }
        return (added, removed)
    }

    /// Physical lines: newline count, plus one for a non-terminated tail. Empty is zero.
    static func lineCount(_ text: String) -> Int {
        var parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.last?.isEmpty == true {
            parts.removeLast()
        }
        return parts.count
    }
}
