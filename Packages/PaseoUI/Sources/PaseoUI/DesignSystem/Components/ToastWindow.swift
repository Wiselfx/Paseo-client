#if canImport(UIKit)
import SwiftUI
import UIKit

/// A window that passes every touch through except the toast's Undo button.
final class ToastWindow: UIWindow {
    var interactiveRect: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !interactiveRect.isNull, interactiveRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
#endif
