#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

// MARK: - Tray pill views

/// One attachment pill in the tray: a 56 pt thumbnail (images) or a file capsule,
/// a thin progress ring while uploading, a retry on failure, a remove "x" always.
///
/// J3 §1: every dimmer, ring and badge is an `.overlay` on the pill's own framed body, never a
/// member of the stack that decides its size. A `Circle()` with no frame is flexible, so inside a
/// `ZStack` it takes the whole proposed size and grows the tile, the tray and the composer card
/// (a pasted screenshot used to fill the composer with a grey disc). An overlay is proposed the
/// size of the view it covers, so nothing in it can size the tile.
struct ComposerAttachmentPill: View {
    let item: ComposerAttachmentItem
    /// Live upload progress of the one item that holds the wire right now (0…1).
    let uploadProgress: Double
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onTapImage: (UIImage) -> Void

    /// The thumbnail tile's edge length (the file and forge pills are 56 pt tall).
    private static let tileSize: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pill
                // The pill is one element; the remove button stays a separate action, so
                // VoiceOver can remove an attachment without opening it.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText)
            removeButton
        }
    }

    @ViewBuilder private var pill: some View {
        if case .attached(let attachment) = item.phase {
            forgePill(attachment)
        } else if case .decoding = item.phase {
            decodingTile
        } else if item.isImage, let thumbnail = item.thumbnail {
            Button {
                if case .failed = item.phase {
                    onRetry()
                } else {
                    onTapImage(thumbnail)
                }
            } label: {
                thumbnailTile(thumbnail)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Image \(item.fileName)")
        } else {
            filePill
        }
    }

    /// An image tile: the thumbnail is the tile's shape and its size, and every phase's chrome is
    /// an overlay on it (J3 §1). Nothing here can propose a size, so the tray keeps its 56 pt.
    private func thumbnailTile(_ thumbnail: UIImage) -> some View {
        Image(uiImage: thumbnail)
            .resizable()
            .scaledToFill()
            .frame(width: Self.tileSize, height: Self.tileSize)
            .clipShape(.rect(cornerRadius: Radius.md))
            .overlay {
                if case .uploading = item.phase {
                    // The wash is the tile, clipped like it; the ring keeps its own 40 pt frame.
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md).fill(Palette.mediaDim)
                        Circle()
                            .trim(from: 0, to: max(0.05, uploadProgress))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .overlay {
                if case .failed = item.phase {
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

    /// A file, or an image whose bytes are still being read: the capsule holds the tray's 56 pt
    /// row and the spinner is centred on its icon well.
    private var filePill: some View {
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
                        .font(.paseo(.caption2))
                        .foregroundStyle(Palette.failureInk)
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                } else if item.byteCount > 0 {
                    Text(ComposerImageProcessor.byteCountText(item.byteCount))
                        .font(.paseo(.caption2))
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
        .frame(minHeight: Self.tileSize)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
    }

    /// The progress ring (uploading) or the spinner (a file's bytes are still being read) on the
    /// icon well. Both are framed or framed-by-overlay, so the pill's height cannot move.
    @ViewBuilder private var fileIconChrome: some View {
        if case .uploading = item.phase {
            Circle()
                .trim(from: 0, to: max(0.05, uploadProgress))
                .stroke(Palette.ink.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))
        } else if case .decoding = item.phase {
            // A picked file's bytes are read off main; the tile holds its place.
            InlineProgress()
        }
    }

    private var accessibilityText: String {
        switch item.phase {
        case .decoding: "\(item.fileName), preparing"
        case .pending: "\(item.fileName), waiting to upload"
        case .uploading: "\(item.fileName), uploading"
        case .done: "\(item.fileName), uploaded"
        case .attached(let attachment): forgeRemoveLabel(attachment)
        case .failed(let message): "\(item.fileName), failed: \(message)"
        }
    }

    /// Upstream's pill remove label: "Remove {{kind}} {{number}}".
    private func forgeRemoveLabel(_ attachment: AgentAttachment) -> String {
        switch attachment {
        case .forgeChangeRequest(let forge):
            "Remove \(forge.forge?.lowercased() == "gitlab" ? "MR" : "PR") \(forge.number)"
        case .forgeIssue(let forge): "Remove issue \(forge.number)"
        default: "Remove attachment"
        }
    }

    /// The placeholder while the bytes are read: a framed tile with the app's inline spinner.
    private var decodingTile: some View {
        ZStack {
            Palette.chip
            InlineProgress()
        }
        .frame(width: Self.tileSize, height: Self.tileSize)
        .clipShape(.rect(cornerRadius: Radius.md))
        .accessibilityLabel("Preparing \(item.fileName)")
    }

    /// A forge issue/change-request pill: kind icon, "#42" and the kind word.
    private func forgePill(_ attachment: AgentAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: forgeSymbol(attachment))
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.paseo(.caption, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                Text(forgeKindWord(attachment))
                    .font(.paseo(.caption2))
                    .foregroundStyle(Palette.tertiaryInk)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Palette.cardBorder, lineWidth: 1)
        }
    }

    private func forgeSymbol(_ attachment: AgentAttachment) -> String {
        switch attachment {
        case .forgeChangeRequest: "arrow.triangle.branch"
        case .forgeIssue: "exclamationmark.circle"
        default: "doc"
        }
    }

    private func forgeKindWord(_ attachment: AgentAttachment) -> String {
        switch attachment {
        case .forgeChangeRequest(let forge):
            forge.forge?.lowercased() == "gitlab" ? "Merge request" : "Pull request"
        case .forgeIssue: "Issue"
        default: "Attachment"
        }
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark")
                .font(.glyph(.small, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Palette.mediaControl, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
        .accessibilityLabel("Remove attachment")
    }
}
#endif
