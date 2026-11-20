#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The detached half: base64 decode, thumbnail downscale and line split, all plain values.
struct DecodedFile: @unchecked Sendable {
    enum Payload {
        case text(String, [String])
        case image(Data, UIImage)
        case svg(String)
        case binary
    }

    let payload: Payload

    init(file: FileExplorerFile, maxPixel: Int) {
        switch file.kind {
        case .image:
            guard let content = file.content,
                let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters)
            else {
                payload = .binary
                return
            }
            let ext = file.path.split(separator: ".").last?.lowercased()
            if ext == "svg", let source = String(data: data, encoding: .utf8) {
                payload = .svg(source)
            } else if let image = Self.downscaled(data, maxPixel: maxPixel) {
                payload = .image(data, image)
            } else {
                payload = .binary
            }
        case .text:
            guard let text = file.textContent else {
                payload = .binary
                return
            }
            payload = .text(text, text.splitLines())
        case .binary, .unknown:
            payload = .binary
        }
    }

    /// UIKit's `UIImage(data:)` decodes lazily on first draw and at full size; this decodes once,
    /// down to the screen, with the `CGImageSource` thumbnail API.
    private static func downscaled(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: image)
        }
        return UIImage(data: data)
    }
}
#endif
