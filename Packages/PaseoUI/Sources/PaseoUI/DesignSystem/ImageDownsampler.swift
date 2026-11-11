#if canImport(UIKit)
import ImageIO
import UIKit

/// One ImageIO downsample for the whole app: read the header, make a **single** thumbnail at the
/// size it will be drawn at, and never materialise the full bitmap. A 4000 px photo costs a
/// 1200 px buffer instead of 48 MB. Safe off the main actor; the caller owns the `UIImage`.
///
/// `kCGImageSourceThumbnailMaxPixelSize` bounds the *longest* side. That is the right rule for a
/// composer attachment (bounded message size) and the wrong one for a full-width card: a tall
/// portrait capped by height would be drawn wider than it was decoded and come out blurry, so
/// the width-exact entry point below does the arithmetic from the source's own pixel size.
enum ImageDownsampler {
    /// The image's drawn pixel size: stored size, swapped for the four transposed EXIF
    /// orientations. Nil when the data carries no usable header.
    static func orientedPixelSize(of source: CGImageSource) -> CGSize? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        // 5…8 rotate by 90°: what is stored as width is drawn as height.
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Longest side at most `maxPixelSize`; never upscales. Animated GIFs yield frame 0 only.
    static func image(data: Data, maxPixelSize: Double) -> UIImage? {
        guard let source = makeSource(data) else { return nil }
        return thumbnail(source, maxSide: maxPixelSize)
    }

    /// The width lands on `pixelWidth` and no side goes above `maxSide`; never upscales.
    static func image(data: Data, pixelWidth: Double, maxSide: Double) -> UIImage? {
        guard pixelWidth >= 1, let source = makeSource(data) else { return nil }
        guard let size = orientedPixelSize(of: source) else {
            // A decodable image with no readable header: fall back to the longest-side rule so
            // the picture still appears, only possibly smaller.
            return thumbnail(source, maxSide: maxSide)
        }
        let longest = max(size.width, size.height)
        let scale = min(1, pixelWidth / size.width, maxSide / longest)
        return thumbnail(source, maxSide: longest * scale)
    }

    private static func makeSource(_ data: Data) -> CGImageSource? {
        guard !data.isEmpty else { return nil }
        // `ShouldCache: false` keeps the full-resolution bitmap out of memory; only the
        // thumbnail below is ever materialised.
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        return source
    }

    private static func thumbnail(_ source: CGImageSource, maxSide: Double) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxSide.rounded(.up)),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
