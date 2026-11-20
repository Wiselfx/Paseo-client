#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

struct ComposerAttachmentItem: Identifiable {
    let id = UUID()
    var fileName: String
    var mimeType: String
    var byteCount: Int
    var data: Data
    /// Pre-downscaled thumbnail for images (nil for files).
    var thumbnail: UIImage?
    var phase: ComposerAttachmentPhase = .pending

    var isImage: Bool { thumbnail != nil }
}
#endif
