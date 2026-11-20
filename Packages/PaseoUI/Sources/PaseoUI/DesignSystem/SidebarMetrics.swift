#if canImport(UIKit)
import CoreGraphics

/// The sidebar's rows.
enum SidebarMetrics {
    /// The usage footer's line height, for the meter rows **and** the status line they replace.
    /// Both are single `.caption` rows with the same `minHeight`, so the footer cannot change
    /// height when the first load lands and the page above it cannot jump (H4 §2).
    static let usageLineHeight: CGFloat = 20

    /// Every usage meter is one size: the footer's rows and the sheet's window rows each draw the
    /// same height, and a footer row's bar never changes width from row to row.
    static let usageMeterWidth: CGFloat = 44
    static let usageDetailMeterWidth: CGFloat = 240
    static let usageMeterHeight: CGFloat = 3
}
#endif
