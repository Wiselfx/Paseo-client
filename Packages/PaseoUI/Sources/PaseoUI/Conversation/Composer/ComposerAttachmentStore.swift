#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

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
#endif
