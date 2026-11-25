#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Render model

/// The inputs a file's `FileRenderModel` is built from. The viewer rebuilds the model only when this
/// key changes, so a resize re-decodes a raster image and nothing else.
struct FileRenderKey: Hashable {
    let path: String
    let revision: String
    let dark: Bool
    /// The largest edge, in pixels, that `DecodedFile` downscales a raster image to. Zero for every
    /// other kind, which never reads it, so their key is the same at any viewer size.
    let pixelBudget: Int
}

extension FileExplorerFile {
    /// Whether `DecodedFile` downscales this file to a pixel budget: raster images only. An SVG is
    /// vector source, drawn by the web view, and text is never downscaled.
    var usesPixelBudget: Bool {
        kind == .image && path.split(separator: ".").last?.lowercased() != "svg"
    }
}
#endif
