#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

// MARK: - Image downscaling

enum ComposerImageProcessor {
    static let maxPixel: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.85

    /// Decodes, scales to fit `maxPixel` on the long edge (never upscaling), re-encodes as JPEG.
    /// Returns nil when the data doesn't decode.
    static func downscaledJPEG(data: Data) -> (data: Data, image: UIImage)? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixel / max(size.width, size.height))
        let target = CGSize(
            width: max(1, (size.width * scale).rounded(.down)),
            height: max(1, (size.height * scale).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else { return nil }
        return (jpeg, scaled)
    }

    /// Decode + downscale with ImageIO, without a full `UIImage` pass: `ImageDownsampler` reads
    /// the header, creates one thumbnail at `maxPixelSize` and never materializes the full
    /// bitmap. Safe off main (audit B N7). One implementation for the app (H5 round 2).
    nonisolated static func thumbnail(data: Data, maxPixelSize: Double) -> UIImage? {
        ImageDownsampler.image(data: data, maxPixelSize: maxPixelSize)
    }

    /// Byte count for display.
    static func byteCountText(_ bytes: Int) -> String {
        PaseoFormat.bytes(bytes)
    }
}
#endif
