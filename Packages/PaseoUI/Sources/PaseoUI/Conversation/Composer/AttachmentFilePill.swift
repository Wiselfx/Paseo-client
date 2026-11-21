#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// A file, or an image whose bytes are still being read: the capsule holds the tray's 56 pt row
/// and the spinner is centred on its icon well.
struct AttachmentFilePill: View {
    let item: ComposerAttachmentItem
    /// Where the uploading ring reads its progress.
    let uploads: ConversationUpload?
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.glyph(.large, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 36, height: 36)
                .overlay { fileIconChrome }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 110, alignment: .leading)
                if case .failed(let message) = item.phase {
                    Text(message)
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.failureInk)
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                } else if item.byteCount > 0 {
                    Text(ComposerImageProcessor.byteCountText(item.byteCount))
                        .font(.paseo(.caption))
                        .foregroundStyle(Palette.tertiaryInk)
                        .lineLimit(1)
                }
            }
            // Nothing to retry while the bytes are missing: the pick itself failed.
            if case .failed = item.phase, !item.data.isEmpty {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.glyph(.small, weight: .medium))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // A full 44 pt target that reaches into the tile's own padding, so the tile keeps
                // its height.
                .padding(.vertical, -7)
                .accessibilityLabel("Retry upload")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // `minHeight`: a fixed one clips the name at accessibility text sizes.
        .frame(minHeight: ComposerAttachmentPill.tileSize)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
    }

    /// The progress ring (uploading) or the spinner (a file's bytes are still being read) on the
    /// icon well. Both are framed or framed-by-overlay, so the pill's height cannot move.
    @ViewBuilder private var fileIconChrome: some View {
        if case .uploading = item.phase {
            UploadProgressRing(uploads: uploads, diameter: 32, tint: Palette.ink.opacity(0.55))
        } else if case .decoding = item.phase {
            // A picked file's bytes are read off main; the tile holds its place.
            InlineProgress()
        }
    }
}
#endif
