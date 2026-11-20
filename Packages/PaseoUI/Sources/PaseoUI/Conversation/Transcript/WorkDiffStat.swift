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
}
#endif
