#if canImport(UIKit)
import SwiftUI
import PaseoStore

/// M8d: @-mentions of files in the composer. `MentionIndex` lazily walks the open workspace's
/// tree once per conversation (breadth-first, pruned and capped); the popover filters in memory.
/// Lives in the composer's slash-menu slot; taps on folders drill in.

struct MentionIndexRow: Identifiable, Hashable {
    var path: String
    var isDirectory: Bool

    var id: String { path }
}
#endif
