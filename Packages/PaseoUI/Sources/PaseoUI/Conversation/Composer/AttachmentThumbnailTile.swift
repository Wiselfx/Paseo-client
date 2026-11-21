#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// An image tile in the attachment tray: the thumbnail is the tile's shape and its size, and every
/// phase's chrome is an overlay on it (J3 §1). Nothing here can propose a size, so the tray keeps
/// its 56 pt.
struct AttachmentThumbnailTile: View {
    let thumbnail: UIImage
    let phase: ComposerAttachmentPhase
    /// Where the uploading ring reads its progress.
    let uploads: ConversationUpload?

    var body: some View {
        Image(uiImage: thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: ComposerAttachmentPill.tileSize, height: ComposerAttachmentPill.tileSize)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                if case .uploading = phase {
                    // The wash is the tile, clipped like it; the ring keeps its own 40 pt frame.
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md).fill(Palette.mediaDim)
                        UploadProgressRing(uploads: uploads, diameter: 40, tint: .white)
                    }
                }
            }
            .overlay {
                if case .failed = phase {
                    ZStack {
                        Palette.mediaScrim
                        Image(systemName: "arrow.clockwise")
                            .font(.glyph(.regular, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .contentShape(.rect)
    }
}
#endif
