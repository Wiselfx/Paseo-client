#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

// MARK: - Animated frames (G3: GIF/APNG animate here only)

// NOTE: RemoteImagePipeline/G3: stills stay stills everywhere; only this decoder animates,
// and only from bytes the pipeline already carried (`MediaPayload.fullData`, ≤ 8 MB).

/// Decodes the frames of a small animated image at display width, off main. Bounded
/// (48 frames) so a pathological GIF cannot eat the viewer; the caller runs it detached.
enum AnimatedImageDecoder {
    static let maxFrames = 48
    static let minFrameDuration = 0.02

    static func animatedImage(data: Data, pixelWidth: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 1 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, 1),
        ]
        var frames: [UIImage] = []
        frames.reserveCapacity(count)
        var duration = 0.0
        for index in 0..<count {
            guard
                let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source, index, options as CFDictionary)
            else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDelay(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(duration, Double(frames.count) * minFrameDuration))
    }

    /// The GIF delay, else the floor. Unequal frame lengths collapse to the mean — the
    /// inaccuracy is invisible at these sizes; the alternative (a custom display-link player)
    /// is a second video stack for a sticker format. Non-GIF animation runs at the floor
    /// rather than freezing: there is no gate-verifiable per-frame delay API for APNG/WebP.
    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
            let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0
        else { return minFrameDuration }
        return delay
    }
}
#endif
