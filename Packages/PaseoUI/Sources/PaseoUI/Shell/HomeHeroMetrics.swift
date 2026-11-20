#if canImport(UIKit)
import SwiftUI

/// Metrics shared by the one home geometry (E2 §3).
enum HomeHeroMetrics {
    /// The home header's resting height: `ShellHeader`'s 48 pt row (its own `minHeight`). A page
    /// that draws no header — the launch frame — reserves exactly this, so the hero sits where
    /// the draft draws it and the hand-off moves nothing (H4 §1). It is the exact height, not an
    /// estimate: the draft's header title is bar chrome and is capped so its line box never makes
    /// the row taller (`DraftChatView.header`), and `EmptyMain`'s title is empty.
    static let headerHeight: CGFloat = 48
    /// The draft's resting chrome under the hero: its workspace line (28 pt + 4 pt) and its
    /// one-line composer (48 pt + 8 pt). Screens with no footer of their own reserve exactly this
    /// strip, so the greeting sits where the draft draws it and the hand-off moves nothing.
    static let draftChrome: CGFloat = 88
}
#endif
