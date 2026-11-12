import Foundation

/// Allocates measured cell widths. Short tables fill the viewport; wide tables scroll.
/// The width cap is a host presentation choice, not a claim about uncaptured Claude tables.
public enum MarkdownTableMetrics {
    public static func columnWidths(idealWidths: [Double], availableWidth: Double, maximumColumnWidth: Double = 174)
        -> [Double]
    {
        guard !idealWidths.isEmpty else { return [] }
        let cap = maximumColumnWidth.isFinite ? max(24, maximumColumnWidth) : 174
        let widths = idealWidths.map { $0.isFinite ? min(cap, max(24, $0)) : cap }
        guard availableWidth.isFinite, availableWidth > 0 else { return widths }
        let equal = availableWidth / Double(widths.count)
        if widths.allSatisfy({ $0 <= equal }) { return Array(repeating: equal, count: widths.count) }
        let extra = max(0, availableWidth - widths.reduce(0, +)) / Double(widths.count)
        return widths.map { $0 + extra }
    }
}

#if canImport(UIKit)
    import PaseoStore
    import SwiftUI

    /// One measured table: column widths plus row heights, both in points.
    final class TablePlanBox: @unchecked Sendable {
        let widths: [CGFloat]
        let heights: [CGFloat]

        init(widths: [CGFloat], heights: [CGFloat]) {
            self.widths = widths
            self.heights = heights
        }
    }

    /// The plan cache (Phase C §9.1): one entry per table key, bounded like the
    /// prose cache. The `Layout` cache reads it as the first-pass seed, so
    /// scrolling back never remeasures; the view reads it for its pin/overflow
    /// decisions on frame one. `NSCache` is thread-safe; entries are replaced,
    /// never mutated, and the grow-only merge keeps columns from ever narrowing.
    enum MarkdownTablePlanCache {
        nonisolated(unsafe) private static let table: NSCache<NSString, TablePlanBox> = {
            let cache = NSCache<NSString, TablePlanBox>()
            cache.countLimit = 64
            return cache
        }()

        static func lookup(key: String) -> TablePlanBox? {
            table.object(forKey: key as NSString)
        }

        static func store(widths: [CGFloat], heights: [CGFloat], key: String) {
            if let cached = lookup(key: key), cached.widths.count == widths.count {
                let merged = zip(cached.widths, widths).map { max($0, $1) }
                table.setObject(
                    TablePlanBox(widths: merged, heights: heights),
                    forKey: key as NSString)
            } else {
                table.setObject(
                    TablePlanBox(widths: widths, heights: heights),
                    forKey: key as NSString)
            }
        }
    }

    /// The measuring layout: cell sizes are read once per table, then cached.
    /// `makeCache` seeds from the plan cache (scroll-backs measure nothing);
    /// `updateCache` remeasures only when the cell count or column count changes
    /// (a streamed row) and merges grow-only through the plan cache. Steady-state
    /// layout passes — every scroll frame — measure nothing.
    struct ClaudeMarkdownTableLayout: Layout {
        var columns: Int
        var availableWidth: CGFloat
        var maximumColumnWidth: CGFloat
        var cacheKey: String

        struct Cache {
            var key: String = ""
            var columns: Int = 0
            var cellCount: Int = 0
            var widths: [CGFloat] = []
            var heights: [CGFloat] = []
        }

        private func measured(_ subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
            guard columns > 0 else { return ([], []) }
            var ideals = Array(repeating: 0.0, count: columns)
            for index in subviews.indices {
                ideals[index % columns] = max(
                    ideals[index % columns], subviews[index].sizeThatFits(.unspecified).width)
            }
            let widths = MarkdownTableMetrics.columnWidths(
                idealWidths: ideals, availableWidth: availableWidth,
                maximumColumnWidth: maximumColumnWidth)
            var heights = Array(repeating: 0.0, count: (subviews.count + columns - 1) / columns)
            for index in subviews.indices {
                heights[index / columns] = max(
                    heights[index / columns],
                    subviews[index].sizeThatFits(.init(width: widths[index % columns], height: nil)).height)
            }
            return (widths.map { CGFloat($0) }, heights.map { CGFloat($0) })
        }

        private func adopt(
            _ measured: (widths: [CGFloat], heights: [CGFloat]), subviews: Subviews
        ) -> Cache {
            let widths = MarkdownTablePlan.mergedWidths(
                cached: MarkdownTablePlanCache.lookup(key: cacheKey).flatMap { seed in
                    seed.widths.count == measured.widths.count
                        ? seed.widths.map(Double.init) : nil
                },
                fresh: measured.widths.map(Double.init)).map(CGFloat.init)
            MarkdownTablePlanCache.store(widths: widths, heights: measured.heights, key: cacheKey)
            return Cache(
                key: cacheKey, columns: columns, cellCount: subviews.count,
                widths: widths, heights: measured.heights)
        }

        func makeCache(subviews: Subviews) -> Cache {
            if let seed = MarkdownTablePlanCache.lookup(key: cacheKey),
                seed.widths.count == columns
            {
                // Seeded: remounts lay out with zero measurement. The heights ride
                // along only when they cover every row; otherwise this pass measures.
                let rows = (subviews.count + columns - 1) / columns
                if seed.heights.count == rows {
                    return Cache(
                        key: cacheKey, columns: columns, cellCount: subviews.count,
                        widths: seed.widths, heights: seed.heights)
                }
            }
            return adopt(measured(subviews), subviews: subviews)
        }

        func updateCache(_ cache: inout Cache, subviews: Subviews) {
            guard subviews.count != cache.cellCount || columns != cache.columns else { return }
            cache = adopt(measured(subviews), subviews: subviews)
        }

        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
        ) -> CGSize {
            if cache.key != cacheKey || cache.columns != columns
                || cache.cellCount != subviews.count
            {
                cache = adopt(measured(subviews), subviews: subviews)
            }
            return CGSize(width: cache.widths.reduce(0, +), height: cache.heights.reduce(0, +))
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
            cache: inout Cache
        ) {
            guard columns > 0, cache.widths.count == columns else { return }
            var x = bounds.minX, y = bounds.minY
            for index in subviews.indices {
                let column = index % columns, row = index / columns
                guard column < cache.widths.count, row < cache.heights.count else { continue }
                if column == 0 {
                    x = bounds.minX
                    if row > 0 { y += cache.heights[row - 1] }
                }
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: .init(width: cache.widths[column], height: cache.heights[row]))
                x += cache.widths[column]
            }
        }
    }

    /// Pure placement: fixed widths and heights, zero measurement. The pinned
    /// rest-stack uses it with the numbers both stacks share from the plan cache,
    /// so the pinned column's rows can never drift out of alignment.
    struct FixedTableLayout: Layout {
        var columns: Int
        var widths: [CGFloat]
        var heights: [CGFloat]

        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) -> CGSize {
            CGSize(width: widths.reduce(0, +), height: heights.reduce(0, +))
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
            cache: inout ()
        ) {
            guard columns > 0, widths.count == columns else { return }
            var x = bounds.minX, y = bounds.minY
            for index in subviews.indices {
                let column = index % columns, row = index / columns
                guard column < widths.count, row < heights.count else { continue }
                if column == 0 {
                    x = bounds.minX
                    if row > 0 { y += heights[row - 1] }
                }
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: .init(width: widths[column], height: heights[row]))
                x += widths[column]
            }
        }
    }
#endif
