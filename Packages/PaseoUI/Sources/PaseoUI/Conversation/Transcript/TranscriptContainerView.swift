#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Views

/// Holds the collection view. The collection view reaches `overscan` points above the top of the
/// screen: the rows there are laid out but never seen, so content that slides down into view (the
/// keyboard closing, a jump, a fast flick toward older turns) is already built when it arrives.
final class TranscriptContainerView: UIView {
    static let overscan: CGFloat = 400
    let collectionView: TranscriptCollectionView
    init(layout: UICollectionViewLayout) {
        collectionView = TranscriptCollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        clipsToBounds = false
        backgroundColor = .clear
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = CGRect(
            x: 0, y: -Self.overscan, width: bounds.width, height: bounds.height + Self.overscan)
        if collectionView.frame != frame { collectionView.frame = frame }
    }
}
#endif
