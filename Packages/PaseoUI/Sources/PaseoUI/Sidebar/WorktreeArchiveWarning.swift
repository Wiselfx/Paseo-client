#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The payload for the "Archive worktree?" destructive confirmation: the counts to show.
struct WorktreeArchiveWarning {
    let workspace: WorkspaceDescriptor
    let message: String
}
#endif
