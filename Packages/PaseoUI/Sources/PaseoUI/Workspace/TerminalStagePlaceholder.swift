#if canImport(UIKit)
import SwiftUI

/// What the stage shows while no emulator is mounted: the host is too old, there are no
/// terminals yet, or the list is still catching up with the selection.
struct TerminalStagePlaceholder: View {
    let isSupported: Bool
    let hasTerminals: Bool
    let onCreate: () -> Void

    var body: some View {
        if !isSupported {
            EmptyState(
                systemImage: "info.circle",
                title: "Update the host to view terminals.",
                message: "This host predates the terminal replay protocol.")
                .padding(.horizontal, Space.xxxl)
                .transition(.opacity)
        } else if !hasTerminals {
            EmptyState(
                systemImage: "apple.terminal",
                title: "No terminals yet",
                message: "Start one to run commands in this workspace.",
                action: (title: "New terminal", run: onCreate))
                .padding(.horizontal, Space.xxxl)
                .transition(.opacity)
        } else {
            // The selected id is stale during the same frame the data refreshes.
            LoadingState().transition(.opacity)
        }
    }
}
#endif
