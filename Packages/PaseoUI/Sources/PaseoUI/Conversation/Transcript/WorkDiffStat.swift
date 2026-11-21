#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One edit's `+N −M`, through the merged call's cached parse. Nil for anything but an edit.
enum WorkDiffStat {
    @MainActor static func of(_ call: ToolCall) -> (added: Int, removed: Int)? {
        guard case .edit(let path, _, _, _) = call.detail else { return nil }
        let merged = ClaudeMergedFileCall(
            kind: .edit, path: path, firstRowId: call.callId, calls: [call], rowSeqEnds: [])
        return merged.diffStat
    }

    /// `+N −M` as it is spoken: "12 lines added, 3 removed". Nil when neither side changed.
    static func spokenText(added: Int, removed: Int) -> String? {
        let lines = { (count: Int) -> String in count == 1 ? "1 line" : "\(PaseoFormat.integer(count)) lines" }
        switch (added > 0, removed > 0) {
        case (true, true): return "\(lines(added)) added, \(PaseoFormat.integer(removed)) removed"
        case (true, false): return "\(lines(added)) added"
        case (false, true): return "\(lines(removed)) removed"
        case (false, false): return nil
        }
    }
}
#endif
