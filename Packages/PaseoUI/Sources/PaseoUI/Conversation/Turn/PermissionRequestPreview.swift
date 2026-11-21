#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI
import UIKit

/// What is being requested, from the daemon's normalized tool call when it
/// could build one: the diff for an edit, the command for a shell, the path
/// for a read/write or fetch. Falls back to the generic description plus the
/// raw input dump. Existing views only — no new renderers.
struct PermissionRequestPreview: View {
    let detail: ToolCallDetail?
    let input: JSONValue?

    var body: some View {
        switch detail {
        case .edit(let path, _, _, let diff)?:
            if let diff, !diff.isEmpty {
                ClaudeDiffView(path: path, unifiedDiff: diff, old: nil, new: nil)
            } else {
                PermissionPathRow(path: path)
            }
        case .shell(let command, _, _, _)?:
            ClaudeCodeBlock(command: command, output: nil, maxHeight: 180)
        case .read(let path, _)?, .write(let path, _)?:
            PermissionPathRow(path: path)
        case .fetch(let url, _, _)?:
            PermissionPathRow(path: url)
        default:
            // The description already renders above; this is only the raw input dump.
            if let input {
                ClaudeCodeBlock(output: ClaudeToolCallDetail.describe(input), maxHeight: 180)
            }
        }
    }
}
#endif
