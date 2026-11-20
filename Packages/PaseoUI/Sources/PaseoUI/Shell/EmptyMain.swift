#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// No agent and no draft: the brand mark, and a retry when the agent list failed (R5 §4.4).
struct EmptyMain: View {
    let session: HostSession
    let onOpenSidebar: () -> Void

    private func refreshAgents() {
        Task { await session.refreshAgents() }
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
            if let error = session.agentsError {
                InlineBanner(.failure, title: error, action: ("Try again", refreshAgents))
                    .padding(.horizontal, Space.lg)
                    .padding(.bottom, Space.xl)
            }
        }
    }
}
#endif
