#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Shared composer pieces

/// V5 §3: a long draft must never push the composer's controls under the keyboard. The field grows
/// to this many lines and then scrolls inside itself — `TextField(axis: .vertical)` scrolls once it
/// reaches its line limit.
enum ComposerFieldLimit {
    /// The limit before the screen has been measured.
    static let unmeasured = 9

    /// About 40 % of the space above the keyboard, in text lines of the 17 pt composer face
    /// (≈ 8 lines on an iPhone in portrait). Clamped so an unmeasured pass still leaves a usable
    /// field, and a tall screen can never take more than a third of the card.
    static func lines(
        availableHeight: CGFloat, fontSize: CGFloat = Typography.chatBodySize
    ) -> Int {
        guard availableHeight > 0 else { return unmeasured }
        let lineHeight = fontSize * 1.4
        return min(10, max(3, Int((availableHeight * 0.4) / lineHeight)))
    }
}
#endif
