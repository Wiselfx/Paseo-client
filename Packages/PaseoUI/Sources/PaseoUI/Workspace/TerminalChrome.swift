#if canImport(UIKit)
import SwiftUI

/// The numbers every floating terminal control shares, so no chrome file carries a literal.
enum TerminalChrome {
    /// Every icon control's hit target and visible circle.
    static let hit = Metrics.hitSize
    /// A chip's visible height; the chip's hit frame is `hit` tall around it.
    static let chipVisualHeight: CGFloat = 36
    /// The inset between floating chrome and the stage edge.
    static let edge = Space.sm
    /// The inset used when the dock sits in the top safe-area band, clear of the display corner.
    static let bandEdge = Space.lg
    /// The gap between neighbouring floating controls.
    static let gap = Space.sm
    /// The dock at rest, once it has been idle for `idleDelay`.
    static let idleOpacity = 0.55
    static let idleDelay: Duration = .seconds(3)
    /// A top safe-area band at least this tall holds the dock without touching a terminal cell.
    static let dockBand = hit + Space.sm
    /// The terminal switcher's widest label, so it fits beside the Dynamic Island.
    static let switcherMaxWidth: CGFloat = 120
    /// A chip while it is pressed.
    static let pressedOpacity = 0.7
    /// The key bar: 44 pt keys with a hairline of breathing room above and below.
    static let keyBarInset = Space.xs / 2
    static let keyBarHeight = hit + Space.xs
}
#endif
