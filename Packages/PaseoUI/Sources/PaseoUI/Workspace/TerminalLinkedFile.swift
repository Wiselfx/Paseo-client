#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The target of a terminal local link: `path:line[:col]` (absolute, `~/` or workspace-relative).
struct TerminalLinkedFile: Identifiable {
    let path: String
    let line: Int?
    let col: Int?

    var id: String { "\(path):\(line ?? 0):\(col ?? 0)" }

    /// Sent as-is: the daemon expands `~/` against the host's home and resolves relative paths
    /// against the workspace cwd (upstream `file-explorer/service.ts` → `resolvePathFromBase`).
    /// This device's home directory means nothing on the host.
    var resolvedPath: String { path }
}
#endif
