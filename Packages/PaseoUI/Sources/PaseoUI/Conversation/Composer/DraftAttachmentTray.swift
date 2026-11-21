#if canImport(UIKit)
import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PaseoStore

/// The draft composer's own attachment tray (D2 §3): there is no agent id to key the shared
/// `ComposerAttachmentStore` by yet, so a draft keeps its items here and uploads them through the
/// session's channel before the create request. File loading, the off-main image decode, the serial
/// upload pump and retry are the same shape as the store's, kept out of the view so they can be
/// driven without one.
///
/// Every task holds the tray weakly, and the tray cancels them when it is released (the draft
/// screen is gone): a load or an upload no longer runs on against the session's shared uploader and
/// writes into the state of a view that has left.
@MainActor @Observable
final class DraftAttachmentTray {
    private(set) var items: [ComposerAttachmentItem] = []
    /// What went wrong with a pick or a paste, shown under the field.
    var error: String?

    /// The tray while creation is in flight: it comes back if the shell reports a failure
    /// (D2 §3). Never written after an `await`.
    private var stashed: [ComposerAttachmentItem] = []
    private var pump: Task<Void, Never>?
    private var loads: [Task<Void, Never>] = []
    /// The channel the pump's in-flight upload rides, so a released tray can stop it.
    private var activeUploader: ConversationUpload?

    isolated deinit {
        pump?.cancel()
        for load in loads { load.cancel() }
        activeUploader?.cancel()
    }

    // MARK: Adding

    /// The picker's files are read off the main actor (`PickedFileLoader`): a 40 MB file, or an
    /// iCloud file that still has to download, used to freeze this screen inside
    /// `Data(contentsOf:)`. Each tile is in the tray from the tap — `.decoding` also holds Send
    /// while the bytes load, so a tap cannot overtake the file.
    func addFiles(_ urls: [URL], session: HostSession) {
        loads.append(Task { [weak self] in
            for url in urls {
                let name = url.lastPathComponent
                var item = ComposerAttachmentItem(
                    fileName: name, mimeType: "application/octet-stream", byteCount: 0,
                    data: Data(), thumbnail: nil, phase: .decoding)
                self?.items.append(item)
                let loaded = await PickedFileLoader.load(url, maxBytes: ConversationUpload.maxBytes)
                guard let self else { return }
                switch loaded {
                case .success(let file):
                    item.mimeType = file.mimeType
                    item.data = file.data
                    item.byteCount = file.data.count
                    item.phase = .pending
                    // A tile the user removed while it loaded stays removed.
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = item
                    }
                case .failure(.unopenable):
                    items.removeAll { $0.id == item.id }
                    error = "Couldn't open \(name)."
                case .failure(.unreadable):
                    items.removeAll { $0.id == item.id }
                    error = "Couldn't read \(name)."
                case .failure(.tooLarge):
                    items.removeAll { $0.id == item.id }
                    error = "\(name) is too large (50 MB max)."
                }
            }
            self?.startPump(session: session)
        })
    }

    /// A picked or pasted image: the `.decoding` tile now, the decode and downscale off main, then
    /// the upload.
    func addImage(_ data: Data, fileName: String, session: HostSession) {
        let item = ComposerAttachmentItem(
            fileName: fileName, mimeType: "image/jpeg", byteCount: data.count, data: Data(),
            thumbnail: nil, phase: .decoding)
        items.append(item)
        loads.append(Task { [weak self] in
            let processed = await ComposerImageProcessor.downscaledJPEG(data: data)
            guard let self, let index = items.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            guard let processed else {
                items[index].phase = .failed("Couldn't read that image.")
                return
            }
            items[index].data = processed.data
            items[index].thumbnail = processed.image
            items[index].byteCount = processed.data.count
            items[index].phase = .pending
            startPump(session: session)
        })
    }

    // MARK: Changing

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func retry(_ id: UUID, session: HostSession) {
        setPhase(.pending, for: id)
        startPump(session: session)
    }

    // MARK: Creation hand-off

    /// The tray leaves the field before the hop, with a copy kept for a failed create: once the
    /// shell swaps the conversation in, this view's state is never written again (D2 §3).
    func stashForSubmission() {
        stashed = items
        items = []
    }

    /// Creation failed in the shell: the tray comes back. Anything attached in the meantime wins
    /// over the stash.
    func restoreStash() {
        guard !stashed.isEmpty else { return }
        if items.isEmpty { items = stashed }
        stashed = []
    }

    // MARK: Upload pump

    /// One upload at a time through the session's shared channel; the files ride the create
    /// request as `uploadedFile`s.
    private func startPump(session: HostSession) {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled, let pending = self?.firstPending() {
                self?.setPhase(.uploading, for: pending.id)
                let uploader = session.fileUploader
                self?.activeUploader = uploader
                let result = await uploader.upload(
                    data: pending.data, fileName: pending.fileName, mimeType: pending.mimeType)
                guard let self else { return }
                activeUploader = nil
                guard let index = items.firstIndex(where: { $0.id == pending.id }) else {
                    continue
                }
                if let result {
                    items[index].phase = .done(result)
                } else {
                    items[index].phase = .failed(uploader.error ?? "The upload failed.")
                }
            }
            self?.pump = nil
        }
    }

    private func firstPending() -> ComposerAttachmentItem? {
        items.first { item in
            if case .pending = item.phase { true } else { false }
        }
    }

    private func setPhase(_ phase: ComposerAttachmentPhase, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = phase
    }
}
#endif
