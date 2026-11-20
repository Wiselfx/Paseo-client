#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The directory (projects, date groups, pinned, rows) in a child of the sidebar, so the
/// agent and workspace lists it reads re-run this body only; the sidebar's header, navigation, footer,
/// sheets and dialogs do not re-evaluate when an agent or workspace changes (R-1).
struct SidebarDirectoryHost: View {
    let sidebar: PaseoSidebar

    var body: some View {
        let _ = PaseoPerf.body("SidebarDirectory")
        sidebar.directory(derivations: sidebar.sidebarDerivations())
    }
}
#endif
