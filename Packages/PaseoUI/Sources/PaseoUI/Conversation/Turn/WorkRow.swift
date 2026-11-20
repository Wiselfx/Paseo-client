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
#endif
