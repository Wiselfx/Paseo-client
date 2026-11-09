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
    /// Waiting its turn in the upload pump.
    case pending
    /// Bytes are on the wire; progress comes from the store (`store.uploads.progress`).
    case uploading
    /// Uploaded; the daemon-side reference.
    case done(AgentAttachment.UploadedFileAttachment)
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

    /// Retry for a failed item.
    func retry(_ itemId: UUID, in id: String, store: ConversationStore) {
        setPhase(.pending, for: itemId, in: id)
        pump(id, store: store)
    }

    /// Removes an item; cancels the in-flight upload when there is one (the daemon-side partial
    /// file is abandoned to its stale timeout).
    func remove(_ itemId: UUID, from id: String, store: ConversationStore) {
        items[id]?.removeAll { $0.id == itemId }
        store.cancelUpload()
    }

    /// Drops the successful attachments (the ones that rode this send). Failed ones stay.
    func consumeDoneAttachments(for id: String) {
        items[id]?.removeAll { item in
            if case .done = item.phase { return true }
            return false
        }
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

    /// Byte count for display.
    static func byteCountText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Tray pill views

/// One attachment pill in the tray: a 56 pt thumbnail (images) or a file capsule,
/// a thin progress ring while uploading, a retry on failure, a remove "x" always.
struct ComposerAttachmentPill: View {
    let item: ComposerAttachmentItem
    /// Live upload progress of the one item that holds the wire right now (0…1).
    let uploadProgress: Double
    let onRemove: () -> Void
    let onRetry: () -> Void
    let onTapImage: (UIImage) -> Void

    private let typography = ClaudeTypography()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pill
            removeButton
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var pill: some View {
        if item.isImage, let thumbnail = item.thumbnail {
            Button {
                if case .failed = item.phase {
                    onRetry()
                } else {
                    onTapImage(thumbnail)
                }
            } label: {
                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                    if case .uploading = item.phase {
                        Circle().fill(Color.black.opacity(0.35))
                        Circle()
                            .trim(from: 0, to: max(0.05, uploadProgress))
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                    }
                    if case .failed = item.phase {
                        ZStack {
                            Color.black.opacity(0.45)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Image \(item.fileName)")
        } else {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "doc")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(ClaudePalette.secondaryInk)
                    if case .uploading = item.phase {
                        Circle()
                            .trim(from: 0, to: max(0.05, uploadProgress))
                            .stroke(ClaudePalette.ink.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fileName)
                        .font(typography.sans(12, weight: .medium))
                        .foregroundStyle(ClaudePalette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 110, alignment: .leading)
                    if case .failed(let message) = item.phase {
                        Text(message)
                            .font(typography.sans(10))
                            .foregroundStyle(ClaudePalette.failureInk)
                            .lineLimit(1)
                            .frame(maxWidth: 110, alignment: .leading)
                    } else {
                        Text(ComposerImageProcessor.byteCountText(item.byteCount))
                            .font(typography.sans(10))
                            .foregroundStyle(ClaudePalette.tertiaryInk)
                            .lineLimit(1)
                    }
                }
                if case .failed = item.phase {
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ClaudePalette.secondaryInk)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry upload")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(height: 56)
            .background(ClaudePalette.panel, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(ClaudePalette.cardBorder, lineWidth: 1)
            }
        }
    }

    private var accessibilityText: String {
        switch item.phase {
        case .pending: "\(item.fileName), waiting to upload"
        case .uploading: "\(item.fileName), uploading"
        case .done: "\(item.fileName), uploaded"
        case .failed(let message): "\(item.fileName), failed: \(message)"
        }
    }

    private var removeButton: some View {
        Button {
            onRemove()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.6), in: .circle)
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
