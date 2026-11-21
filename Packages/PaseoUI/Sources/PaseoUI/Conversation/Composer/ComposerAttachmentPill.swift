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
///
/// The tile kinds are views of their own (`AttachmentThumbnailTile`, `AttachmentFilePill`,
/// `AttachmentForgePill`), so a phase change re-runs only the tile that shows it. This view never
/// reads the upload's progress: it hands the observable to the ring, the one view that does.
struct ComposerAttachmentPill: View {
    let item: ComposerAttachmentItem
    /// The channel the one item that holds the wire right now uploads through; the ring reads its
    /// progress (0…1).
    let uploads: ConversationUpload?
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onTapImage: (UIImage) -> Void

    /// The thumbnail tile's edge length (the file and forge pills are 56 pt tall).
    static let tileSize: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pill
                // The pill is one element; the remove button stays a separate action, so
                // VoiceOver can remove an attachment without opening it.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText)
            AttachmentRemoveButton(label: removeLabel, onRemove: onRemove)
        }
    }

    @ViewBuilder private var pill: some View {
        if case .attached(let attachment) = item.phase {
            AttachmentForgePill(item: item, attachment: attachment)
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
                AttachmentThumbnailTile(thumbnail: thumbnail, phase: item.phase, uploads: uploads)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Image \(item.fileName)")
        } else {
            AttachmentFilePill(item: item, uploads: uploads, onRetry: onRetry)
        }
    }

    /// What the pill itself says. The remove button says what it removes (`removeLabel`).
    private var accessibilityText: String {
        switch item.phase {
        case .decoding: "\(item.fileName), preparing"
        case .pending: "\(item.fileName), waiting to upload"
        case .uploading: "\(item.fileName), uploading"
        case .done: "\(item.fileName), uploaded"
        case .attached(let attachment):
            "\(item.fileName), \(AttachmentForgePill.kindWord(attachment))"
        case .failed(let message): "\(item.fileName), failed: \(message)"
        }
    }

    /// The remove button's label, per attachment: with several in the tray, "Remove attachment"
    /// would be the same for each. A forge pill uses upstream's "Remove {{kind}} {{number}}".
    private var removeLabel: String {
        guard case .attached(let attachment) = item.phase else { return "Remove \(item.fileName)" }
        switch attachment {
        case .forgeChangeRequest(let forge):
            return "Remove \(forge.forge?.lowercased() == "gitlab" ? "MR" : "PR") \(forge.number)"
        case .forgeIssue(let forge): return "Remove issue \(forge.number)"
        default: return "Remove \(item.fileName)"
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
}
#endif
