#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The horizontal tray of attachment pills above the field. The upload's progress is not read
/// here: each pill hands the `ConversationUpload` to its ring, so a chunk landing re-runs the ring,
/// not the tray and not the composer.
struct ComposerAttachmentTray: View {
    let items: [ComposerAttachmentItem]
    /// The channel the tray's uploads ride: the conversation's, or the session's in a draft.
    let uploads: ConversationUpload?
    let onRemove: (UUID) -> Void
    let onRetry: (UUID) -> Void
    let onTapImage: (UIImage) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    ComposerAttachmentPill(
                        item: item,
                        uploads: uploads,
                        onRemove: { onRemove(item.id) },
                        onRetry: { onRetry(item.id) },
                        onTapImage: onTapImage)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}
#endif
