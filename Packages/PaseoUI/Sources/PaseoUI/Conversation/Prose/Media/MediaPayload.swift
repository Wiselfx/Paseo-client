#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UIKit

// MARK: - Results

/// A decoded image and the shape it wants to be laid out in.
///
/// A class, not a struct, for two reasons: `NSCache` stores objects, and the payload crosses
/// from the decode task to the main actor. `UIImage` is immutable and safe to hand around;
/// `@unchecked Sendable` states that in one place instead of at every call site.
final class MediaPayload: @unchecked Sendable {
    let image: UIImage
    /// Width / height as decoded, so a card can reserve its box before the pixels land and
    /// never shift what is above or below it.
    let aspectRatio: CGFloat
    /// More than one frame (GIF/APNG/WebP): the transcript shows `image` (the first frame)
    /// with a badge; only the viewer animates.
    let isAnimated: Bool
    /// The full bytes, carried only for small animated images (≤ 8 MB) so the viewer can
    /// decode frames without a second fetch. Nil for stills — they never need it.
    let fullData: Data?

    init(image: UIImage, aspectRatio: CGFloat, isAnimated: Bool = false, fullData: Data? = nil) {
        self.image = image
        self.aspectRatio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        self.isAnimated = isAnimated
        self.fullData = fullData
    }
}
extension MediaPayload {
    /// Animated bytes are worth carrying only when they fit a viewer page comfortably.
    static let maxCarriedAnimationBytes = 8 * 1024 * 1024

    /// The downsample itself, off the pipeline's actor and off main. Width-exact: a tall portrait
    /// is decoded so its **width** matches the card, not its longest side (H5 round 2 review).
    static func decode(data: Data, pixelWidth: Int, maxSide: Double = 2048) -> MediaPayload? {
        guard
            let image = ImageDownsampler.image(
                data: data, pixelWidth: Double(pixelWidth), maxSide: maxSide)
        else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let animated = (frameCount(of: data) ?? 1) > 1
        let fullData = animated && data.count <= maxCarriedAnimationBytes ? data : nil
        return MediaPayload(
            image: image, aspectRatio: size.width / size.height,
            isAnimated: animated, fullData: fullData)
    }

    /// The frame count from the header alone — no bitmap, no decode.
    private static func frameCount(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetCount(source)
    }
}
#endif
