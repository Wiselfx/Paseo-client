#if canImport(UIKit)
import UIKit

/// The key bar's scroller. Touches reach a key at once (no content-touch delay, so a key lights up
/// on touch-down), and a drag that starts on a key cancels the key's touch and scrolls, so
/// scrolling never presses anything.
final class KeyBarScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        isDirectionalLockEnabled = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// A `UIControl` is not cancelled by default, which would make a key swallow the drag.
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}
#endif
