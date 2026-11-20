#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// M6a: composer attachments. Items live in `ComposerAttachmentStore` (app-scope, keyed by
/// agent id) so the tray survives switching agents; they upload at attach time through the
/// conversation's `ConversationUpload` (T14), serially, one file at a time. Lost on relaunch.
///
/// Images are downscaled to max 2048 px JPEG at 0.85 before upload (HEIC included). Sends go
/// through `sendWithAttachments` with `.uploadedFile` references.

// MARK: - Model

enum ComposerAttachmentPhase: Equatable {
    /// Picked but not decoded yet: the tray shows a progress tile (audit B N7/N8 — decoding an
    /// image is off main, so the pill exists before its thumbnail does).
    case decoding
    /// Waiting its turn in the upload pump.
    case pending
    /// Bytes are on the wire; progress comes from the store (`store.uploads.progress`).
    case uploading
    /// Uploaded; the daemon-side reference.
    case done(AgentAttachment.UploadedFileAttachment)
    /// A structured attachment (forge issue/change request) that needs no upload: ready now.
    case attached(AgentAttachment)
    /// The upload failed; retry sets it back to `.pending`.
    case failed(String)
}
#endif
