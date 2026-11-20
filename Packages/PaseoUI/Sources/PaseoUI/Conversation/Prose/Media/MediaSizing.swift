#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

// MARK: - Sizing

enum MediaSizing {
    /// The pixel width to decode at: the card's width in points × the screen scale, rounded up
    /// to a 128 px bucket so a one-point layout change does not throw the decode away.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        guard points > 1, scale > 0 else { return 640 }
        let pixels = points * scale
        let bucket = (pixels / 128).rounded(.up) * 128
        return Int(min(max(bucket, 128), 2048))
    }
}
#endif
