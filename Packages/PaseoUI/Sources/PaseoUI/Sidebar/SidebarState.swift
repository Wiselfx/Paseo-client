#if canImport(UIKit)
import Observation
import PaseoStore

/// The drawer's transient presentation state and its two long-lived owners, held by
/// `PaseoSidebar` in one private `@State`.
///
/// `@State` properties that other files' extensions read cannot be `private`, and a non-private
/// `@State` re-runs its initial expression on every rebuild of the view: `SidebarPreferences()`
/// reads and splits five `UserDefaults` keys, `WorkspaceArchiveActions()` allocates. Here they are
/// created once, and `PaseoSidebar` forwards each property so the extensions stay unchanged.
@MainActor
@Observable
final class SidebarState {
    var sheet: PaseoSidebarSheet?
    var showHidden = false
    var renamingWorkspace: WorkspaceDescriptor?
    var renamingProject: WorkspaceProjectDescriptor?
    var projectPendingRemoval: WorkspaceProjectDescriptor?
    var renameText = ""
    /// The comma-joined preferences, parsed once (§3). Observable on its own.
    let preferences = SidebarPreferences()
    /// The workspace archive flow: the risk check and the two confirmations. Observable on its own.
    let archive = WorkspaceArchiveActions()
}
#endif
