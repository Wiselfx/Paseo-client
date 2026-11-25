#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Layout

/// A vertical stack of self-sizing rows with a fixed gap. Heights are measured once per item and
/// width, remembered by id, and estimated (from remembered heights or the text) until measured.
///
/// When a row above the reader's line changes height — a row measured for the first time while
/// scrolling up, an older page landing — the offset moves by the same amount in the same layout pass
/// (`contentOffsetAdjustment`), so what the reader looks at never moves. A cell that reaches across the
/// line is followed by row instead (`TranscriptEngine.compensatesResize`): the offset moves only by how
/// far the row under the line moved. While the reader follows the tail the engine pins the end after
/// the pass instead.
@MainActor
final class TranscriptLayout: UICollectionViewLayout {
    static let spacing: CGFloat = 27
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 20
    static let sideMargin: CGFloat = 16

    weak var engine: TranscriptEngine?
    /// Horizontal safe area (landscape), added to the side margins.
    var horizontalInsets: (left: CGFloat, right: CGFloat) = (0, 0)

    private(set) var frames: [CGRect] = []
    private var heights: [CGFloat] = []
    private var measured: [TranscriptItemID: CGFloat] = [:]
    private var needsRebuild = true
    private(set) var columnWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0

    /// The item list changed: heights are re-read by id on the next pass.
    func itemsDidChange() { needsRebuild = true }

    /// The measured height of an item, if it was measured at this width.
    func measuredHeight(of id: TranscriptItemID) -> CGFloat? { measured[id] }

    override func prepare() {
        super.prepare()
        guard let collectionView, let engine else {
            frames = []
            heights = []
            contentHeight = 0
            return
        }
        let column = max(
            collectionView.bounds.width - 2 * Self.sideMargin - horizontalInsets.left
                - horizontalInsets.right, 1)
        if abs(column - columnWidth) > 0.5 {
            columnWidth = column
            measured.removeAll()
            needsRebuild = true
            engine.columnWidthChanged()
        }
        let items = engine.items
        if needsRebuild || heights.count != items.count {
            needsRebuild = false
            heights = items.indices.map { index in
                measured[items[index]] ?? engine.estimatedHeight(at: index, column: column)
            }
        }
        let x = Self.sideMargin + horizontalInsets.left
        var y = Self.topPadding
        var placed = false
        frames.removeAll(keepingCapacity: true)
        frames.reserveCapacity(heights.count)
        for height in heights {
            if height > 0 {
                if placed { y += Self.spacing }
                placed = true
            }
            frames.append(CGRect(x: x, y: y, width: column, height: height))
            y += height
        }
        contentHeight = y + Self.bottomPadding
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var result: [UICollectionViewLayoutAttributes] = []
        var index = firstIndex(withMaxYAtLeast: rect.minY)
        while index < frames.count, frames[index].minY <= rect.maxY {
            result.append(attributes(at: index))
            index += 1
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, frames.indices.contains(indexPath.item) else { return nil }
        return attributes(at: indexPath.item)
    }

    private func attributes(at index: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frames[index]
        return attributes
    }

    /// The first item whose bottom is at or below `y`. O(log n).
    func firstIndex(withMaxYAtLeast y: CGFloat) -> Int {
        var low = 0
        var high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxY < y { low = mid + 1 } else { high = mid }
        }
        return low
    }

    func frame(at index: Int) -> CGRect? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        abs(newBounds.width - (collectionView?.bounds.width ?? 0)) > 0.5
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool {
        let index = originalAttributes.indexPath.item
        guard heights.indices.contains(index) else { return false }
        return abs(preferredAttributes.size.height - heights[index]) > 0.5
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes)
        let index = originalAttributes.indexPath.item
        guard let engine, heights.indices.contains(index), engine.items.indices.contains(index),
            frames.indices.contains(index)
        else { return context }
        let old = heights[index]
        let new = max(preferredAttributes.size.height, 0)
        heights[index] = new
        measured[engine.items[index]] = new
        engine.didMeasure(index: index, height: new)
        let delta = new - old
        if engine.compensatesResize(of: frames[index], at: index, delta: delta) {
            context.contentOffsetAdjustment = CGPoint(x: 0, y: delta)
        }
        context.contentSizeAdjustment = CGSize(width: 0, height: delta)
        return context
    }
}
#endif
