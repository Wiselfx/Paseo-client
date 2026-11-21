#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8d: @-mentions of files in the composer. `MentionIndex` lazily walks the open workspace's
/// tree once per conversation (breadth-first, pruned and capped); the popover filters in memory.
/// Lives in the composer's slash-menu slot; taps on folders drill in.

struct MentionIndexRow: Identifiable, Hashable {
    let path: String
    var isDirectory: Bool
    /// What ranking compares against, computed once when the row is built: `MentionIndex.matches`
    /// runs on the main actor for every debounced keystroke over up to 2,000 rows, and its sort
    /// comparator would otherwise split both paths again on every comparison.
    let lowercasedPath: String
    /// The number of path components (`a/b/c` is 3).
    let depth: Int

    var id: String { path }

    init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
        self.lowercasedPath = path.lowercased()
        self.depth = path.split(separator: "/").count
    }
}
#endif
