#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A cell hosting one transcript item in SwiftUI. It sizes itself to the column's width.
final class TranscriptCell: UICollectionViewCell {
    var fixedHeight: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
    }

    required init?(coder: NSCoder) { nil }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes else {
            return layoutAttributes
        }
        if let fixedHeight {
            attributes.size.height = fixedHeight
            return attributes
        }
        let fitting = contentView.systemLayoutSizeFitting(
            CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        attributes.size.height = max(1, (fitting.height * scale).rounded(.up) / scale)
        return attributes
    }
}
#endif
