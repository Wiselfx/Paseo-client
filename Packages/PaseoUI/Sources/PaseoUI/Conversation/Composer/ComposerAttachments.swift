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

// MARK: - Store (app-scope, keyed by agent id)

@MainActor @Observable
final class ComposerAttachmentStore {
    static let shared = ComposerAttachmentStore()

    private var items: [String: [ComposerAttachmentItem]] = [:]
    private var pumps: [String: Task<Void, Never>] = [:]

    private init() {}

    /// The tray for one agent. Empty when nothing is attached.
    func items(for id: String) -> [ComposerAttachmentItem] {
        items[id] ?? []
    }

    /// Adds an item and kicks off the serial upload pump (one upload at a time — the daemon
    /// pipeline is single-stream per conversation).
    func add(_ item: ComposerAttachmentItem, to id: String, store: ConversationStore) {
        items[id, default: []].append(item)
        pump(id, store: store)
    }

    /// Adds a forge issue/change request pick from the search sheet. No bytes, no upload:
    /// the phases ride straight to `sendWithAttachments` as structured attachments.
    func addForge(_ attachment: AgentAttachment, to id: String, store: ConversationStore) {
        let (fileName, mimeType): (String, String)
        switch attachment {
        case .forgeChangeRequest(let forge):
            fileName = "#\(forge.number)"
            mimeType = forge.mimeType
        case .forgeIssue(let forge):
            fileName = "#\(forge.number)"
            mimeType = forge.mimeType
        default:
            fileName = "Attachment"
            mimeType = "application/octet-stream"
        }
        let item = ComposerAttachmentItem(
            fileName: fileName, mimeType: mimeType, byteCount: 0, data: Data(), thumbnail: nil,
            phase: .attached(attachment))
        add(item, to: id, store: store)
    }

    /// Retry for a failed item. Only an item that still has bytes can be re-sent: the retry button
    /// on a pill whose *read* failed (`addImage`/`addFile` decode or file error, no data) has
    /// nothing to upload, and re-phasing it would push a 0-byte file at the agent.
    func retry(_ itemId: UUID, in id: String, store: ConversationStore) {
        guard let item = items[id]?.first(where: { $0.id == itemId }), !item.data.isEmpty else {
            return
        }
        setPhase(.pending, for: itemId, in: id)
        pump(id, store: store)
    }

    /// Removes an item; cancels the in-flight upload when there is one (the daemon-side partial
    /// file is abandoned to its stale timeout).
    func remove(_ itemId: UUID, from id: String, store: ConversationStore) {
        let wasUploading = items[id]?.contains { item in
            guard item.id == itemId, case .uploading = item.phase else { return false }
            return true
        } ?? false
        items[id]?.removeAll { $0.id == itemId }
        // Cancel is whole-conversation: only cancel when the removed pill is the one in flight.
        if wasUploading { store.cancelUpload() }
    }

    /// Drops the successful attachments (the ones that rode this send). Failed ones stay.
    func consumeDoneAttachments(for id: String) {
        items[id]?.removeAll { item in
            switch item.phase {
            case .done, .attached: return true
            case .decoding, .pending, .uploading, .failed: return false
            }
        }
    }

    func resumePump(_ id: String, store: ConversationStore) {
        pump(id, store: store)
    }

    private func pump(_ id: String, store: ConversationStore) {
        guard pumps[id] == nil else { return }
        pumps[id] = Task { @MainActor [weak self] in
            defer { self?.pumps[id] = nil }
            while let item = self?.firstPending(id), let self {
                self.setPhase(.uploading, for: item.id, in: id)
                let result = await store.upload(
                    data: item.data, fileName: item.fileName, mimeType: item.mimeType)
                if let result {
                    self.setPhase(.done(result), for: item.id, in: id)
                } else {
                    self.setPhase(.failed(store.uploads.error ?? "The upload failed."),
                                  for: item.id, in: id)
                }
            }
        }
    }

    private func firstPending(_ id: String) -> ComposerAttachmentItem? {
        items[id]?.first { if case .pending = $0.phase { true } else { false } }
    }

    private func setPhase(_ phase: ComposerAttachmentPhase, for itemId: UUID, in id: String) {
        guard var list = items[id] else { return }
        guard let index = list.firstIndex(where: { $0.id == itemId }) else { return }
        list[index].phase = phase
        items[id] = list
    }
}


extension ComposerAttachmentStore {
    /// Attach an image the user picked. The pill exists immediately in the `.decoding` phase and
    /// the decode/resize/JPEG pass runs **off main** (audit B N7/N8); the item flips to `.pending`
    /// when the bytes are ready and the pump uploads it. A decode failure lands on the pill as a
    /// retryable `.failed`.
    func addImage(data: Data, fileName: String, to id: String, store: ConversationStore) {
        let item = ComposerAttachmentItem(
            fileName: fileName, mimeType: "image/jpeg", byteCount: data.count, data: Data(),
            thumbnail: nil, phase: .decoding)
        add(item, to: id, store: store)
        Task { @MainActor [weak self] in
            let processed = await Task.detached(priority: .userInitiated) {
                ComposerImageProcessor.downscaledJPEG(data: data)
            }.value
            guard let self else { return }
            guard let processed else {
                self.setPhase(.failed("Couldn't read that image."), for: item.id, in: id)
                return
            }
            guard self.replaceData(processed.data, thumbnail: processed.image, for: item.id, in: id)
            else { return }
            self.setPhase(.pending, for: item.id, in: id)
            self.resumePump(id, store: store)
        }
    }

    /// Fills in the decoded bytes for a `.decoding` item. False when the pill was removed.
    @discardableResult
    private func replaceData(
        _ data: Data, thumbnail: UIImage?, for itemId: UUID, in id: String
    ) -> Bool {
        guard var list = items[id], let index = list.firstIndex(where: { $0.id == itemId }) else {
            return false
        }
        list[index].data = data
        list[index].thumbnail = thumbnail
        list[index].byteCount = data.count
        items[id] = list
        return true
    }

    /// Attach a file picked in Files. Same shape as `addImage`: the pill exists immediately in the
    /// `.decoding` phase — which also holds Send while the bytes are read — and the read runs **off
    /// main** (`PickedFileLoader`; an iCloud file that still has to download is seconds of I/O). A
    /// failure lands on the pill as `.failed`, with the copy the toast used to show.
    func addFile(url: URL, to id: String, store: ConversationStore) {
        let item = ComposerAttachmentItem(
            fileName: url.lastPathComponent, mimeType: "application/octet-stream", byteCount: 0,
            data: Data(), thumbnail: nil, phase: .decoding)
        add(item, to: id, store: store)
        Task { @MainActor [weak self] in
            switch await PickedFileLoader.load(url, maxBytes: ConversationUpload.maxBytes) {
            case .success(let file):
                guard let self, self.replaceFile(file, for: item.id, in: id) else { return }
                self.setPhase(.pending, for: item.id, in: id)
                self.resumePump(id, store: store)
            case .failure(.unopenable):
                self?.setPhase(.failed("Couldn't open \(item.fileName)."), for: item.id, in: id)
            case .failure(.unreadable):
                self?.setPhase(.failed("Couldn't read \(item.fileName)."), for: item.id, in: id)
            case .failure(.tooLarge):
                self?.setPhase(
                    .failed("\(item.fileName) is too large (50 MB max)."), for: item.id, in: id)
            }
        }
    }

    /// Fills in a `.decoding` file's bytes and its type. False when the pill was removed.
    private func replaceFile(
        _ file: PickedFileLoader.Loaded, for itemId: UUID, in id: String
    ) -> Bool {
        guard var list = items[id], let index = list.firstIndex(where: { $0.id == itemId }) else {
            return false
        }
        list[index].mimeType = file.mimeType
        list[index].data = file.data
        list[index].byteCount = file.data.count
        items[id] = list
        return true
    }
}

// MARK: - Image downscaling

enum ComposerImageProcessor {
    static let maxPixel: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.85

    /// Decodes, scales to fit `maxPixel` on the long edge (never upscaling), re-encodes as JPEG.
    /// Returns nil when the data doesn't decode.
    static func downscaledJPEG(data: Data) -> (data: Data, image: UIImage)? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxPixel / max(size.width, size.height))
        let target = CGSize(
            width: max(1, (size.width * scale).rounded(.down)),
            height: max(1, (size.height * scale).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = scaled.jpegData(compressionQuality: jpegQuality) else { return nil }
        return (jpeg, scaled)
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
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
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

/// Minimal full-screen image viewer for attachment pills: dark canvas, tap to dismiss.
struct AttachmentImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image viewer, tap to dismiss")
    }
}
#endif
