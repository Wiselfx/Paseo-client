#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// Watches the two session facts the shell reacts to, in its own body, so `ShellView.body` never
/// reads the agent list or the directory state (R5 §4.1). It reacts to the agent ids, not to
/// every snapshot field, so a status change does not re-route anything.
struct ShellSessionWatcher: View {
    let session: HostSession
    let onAgentsChange: () -> Void
    let onDirectoryLoaded: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.agents.map(\.id)) { _, _ in
                onAgentsChange()
            }
            .onChange(of: session.workspaceDirectory.hasLoaded) { _, loaded in
                if loaded { onDirectoryLoaded() }
            }
    }
}
#endif
