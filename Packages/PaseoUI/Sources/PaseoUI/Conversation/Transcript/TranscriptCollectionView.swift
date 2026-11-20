#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The transcript's scroll view. After every layout pass it lets the engine pin the end while the
/// reader follows the tail: one place, one rule, no estimate to chase.
final class TranscriptCollectionView: UICollectionView {
    weak var engine: TranscriptEngine?

    override func layoutSubviews() {
        guard let engine, engine.animatesResizes else {
            super.layoutSubviews()
            engine?.collectionViewDidLayout()
            return
        }
        // Just after a tap (a disclosure): rows a resize moved glide from where they were, in the
        // same curve as the SwiftUI content opening inside its cell.
        var before: [ObjectIdentifier: CGFloat] = [:]
        for cell in visibleCells { before[ObjectIdentifier(cell)] = cell.frame.minY }
        super.layoutSubviews()
        engine.collectionViewDidLayout()
        engine.animateMoves(of: visibleCells, from: before)
    }
}
#endif
