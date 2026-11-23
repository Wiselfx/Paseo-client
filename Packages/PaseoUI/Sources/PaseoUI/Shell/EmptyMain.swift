#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// No agent and no draft: the brand mark, and a retry when the agent list or the workspace
/// directory failed to load (R5 §4.4), so the first screen is never a dead end.
struct EmptyMain: View {
    let session: HostSession
    let onOpenSidebar: () -> Void

    /// The load failure to show: the agent list's, else the workspace directory's.
    private var loadError: String? {
        session.agentsError ?? session.workspaceDirectory.error
    }

    /// Retries both loads, like the sidebar's banner: either one can be what failed.
    private func retry() {
        Task {
            await session.workspaceDirectory.refresh()
            await session.refreshAgents()
        }
    }

    var body: some View {
        // Same geometry as `LaunchSkeleton` and the draft: the header is the page's first row,
        // pinned top-leading, and the hero is centred in the space the draft's composer will take
        // (E2 §3.1, H4 §1).
        HomeHeroLayout {
            ShellHeader(leading: .sidebar(onOpenSidebar)) {
                Color.clear
            } trailing: {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
        } hero: {
            ClaudeHomeHero()
        }
        .overlay(alignment: .bottom) {
            if let error = loadError {
                InlineBanner(.failure, title: error, action: ("Try again", retry))
                    .padding(.horizontal, Space.lg)
                    .padding(.bottom, Space.xl)
            }
        }
    }
}
#endif
