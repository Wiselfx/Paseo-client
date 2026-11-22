#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The directory with no rows: an error is a banner with a retry (PLAN §RI 22); everything else
/// is the quiet line.
struct SidebarEmptyDirectoryState: View {
    let directory: WorkspaceDirectory
    /// A label filter is on, so "no rows" means none carry the label.
    let isFiltered: Bool
    let onRetry: () -> Void

    var body: some View {
        if let error = directory.error, !isFiltered {
            InlineBanner(.failure, title: error, action: ("Try again", onRetry))
                .padding(.vertical, 24)
        } else if directory.isLoading {
            LoadingState("Loading workspaces…")
                .padding(.vertical, 24)
        } else {
            Text(isFiltered ? "No workspaces with this label." : "No workspaces on this host yet.")
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.vertical, 24)
        }
    }
}
#endif
