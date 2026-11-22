#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// The PR pane for the Changes page: title/number/state, review decision, checks with a rollup,
/// an "Open on <forge>" row, and the activity timeline (reviews and comments) with Add-to-chat
/// per check, review and comment. Renders nothing when the branch has no PR.
struct WorkspacePRSection: View {
    let session: HostSession
    let checkout: CheckoutStore

    /// The modern-diff helper's PR status first (T11), the checkout's own otherwise.
    private var status: CheckoutPrStatus? {
        session.gitExtras.workspace(for: checkout).prStatus ?? checkout.prStatus
    }

    var body: some View {
        if let status, !status.url.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.sm) {
                    Text("Pull request")
                        .font(.paseo(.footnote, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.sm)
                PRStateRow(status: status)
                if !status.checks.isEmpty { PRChecksBlock(status: status) }
                PROpenOnForgeRow(status: status)
                // The timeline store is memoized per checkout by the extras store.
                PRActivityBlock(status: status, timeline: session.gitExtras.timeline(for: checkout))
                // Keep the section visually separate from the file list below it.
                ClaudeDivider()
            }
        }
    }
}
#endif
