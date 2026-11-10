#if canImport(UIKit)
import SwiftUI

/// The sidebar's old status dot, kept as a mapping onto the one dot the design system has.
/// New code uses `StatusDot`; the remaining call sites in Conversation, Settings and Workspace
/// migrate in their own tickets.
@available(
    *, deprecated,
    message: "Use StatusDot. R6/R7/R8 migrate their call sites; the sidebar no longer uses this."
)
struct PaseoStatusDot: View {
    enum Kind: Equatable { case running, needsInput, failed, done, unread, idle }

    let kind: Kind

    var body: some View {
        StatusDot(state)
    }

    /// One meaning per dot: a finished workspace is no longer green (UX-SPEC §0.1 keeps green for
    /// diff counts), so `.done` reads as the same quiet dot as `.idle`.
    private var state: StatusDot.State {
        switch kind {
        case .running: .running
        case .needsInput: .attention
        case .failed: .failed
        case .unread: .unread
        case .done, .idle: .idle
        }
    }
}
#endif
