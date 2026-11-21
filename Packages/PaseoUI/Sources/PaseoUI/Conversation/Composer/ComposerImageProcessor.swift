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
    ///
    /// `@concurrent`: the work runs off the caller's actor, stated once here instead of at every
    /// call site. The decode goes through ImageIO (`ImageDownsampler`), which never materializes the
    /// full bitmap: a 48 MP photo would cost about 190 MB through `UIImage(data:)` and `draw(in:)`,
    /// and the picker allows ten at once.
    @concurrent nonisolated static func downscaledJPEG(
        data: Data
    ) async -> (data: Data, image: UIImage)? {
        guard let scaled = ImageDownsampler.image(data: data, maxPixelSize: Double(maxPixel)),
            let jpeg = scaled.jpegData(compressionQuality: jpegQuality)
        else { return nil }
        return (jpeg, scaled)
    }

    /// A camera frame as full-quality JPEG bytes. `@concurrent`: a 12 to 48 MP frame takes tens to
    /// hundreds of milliseconds to encode, which the main actor must not pay while the camera
    /// sheet dismisses. The bytes then go through the same `downscaledJPEG` pass as a picked photo.
    @concurrent nonisolated static func jpegData(of image: UIImage) async -> Data? {
        image.jpegData(compressionQuality: 1.0)
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
