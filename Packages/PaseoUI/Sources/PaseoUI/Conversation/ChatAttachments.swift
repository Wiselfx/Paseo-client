#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension ClaudeChatView {
    // MARK: Attachments (M6a)

    var trayItems: [ComposerAttachmentItem] { attachmentStore.items(for: store.agentId) }

    var hasUploadingAttachment: Bool {
        trayItems.contains { item in
            switch item.phase {
            case .pending, .uploading: true
            case .done, .failed: false
            }
        }
    }

    /// Send is enabled with an empty draft when there's a finished attachment; disabled while an
    /// upload is in flight.
    var canSendMessage: Bool {
        guard !hasUploadingAttachment else { return false }
        if !trimmedDraft.isEmpty { return true }
        return trayItems.contains { item in
            switch item.phase {
            case .done, .attached: return true
            case .pending, .uploading, .failed: return false
            }
        }
    }

    var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// Decodes, downscales to ≤ 2048 px and re-encodes as JPEG (0.85), then attaches.
    func attachImageData(_ data: Data, fileName: String) {
        guard let processed = ComposerImageProcessor.downscaledJPEG(data: data) else {
            showToast("Couldn't read that image.")
            return
        }
        let item = ComposerAttachmentItem(
            fileName: fileName, mimeType: "image/jpeg", byteCount: processed.data.count,
            data: processed.data, thumbnail: processed.image)
        attachmentStore.add(item, to: store.agentId, store: store)
    }

    func handlePickedPhotos(_ selection: [PhotosPickerItem]) {
        Task {
            for picked in selection {
                guard let data = try? await picked.loadTransferable(type: Data.self) else {
                    continue
                }
                attachImageData(data, fileName: "photo-\(UUID().uuidString.prefix(8)).jpg")
            }
            photoSelection = []
        }
    }

    func attachFileURLs(_ urls: [URL]) {
        for url in urls {
            let name = url.lastPathComponent
            guard url.startAccessingSecurityScopedResource() else {
                showToast("Couldn't open \(name).")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else {
                showToast("Couldn't read \(name).")
                continue
            }
            guard data.count <= ConversationUpload.maxBytes else {
                showToast("\(name) is too large (50 MB max).")
                continue
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let item = ComposerAttachmentItem(
                fileName: name, mimeType: mimeType, byteCount: data.count,
                data: data, thumbnail: nil)
            attachmentStore.add(item, to: store.agentId, store: store)
        }
    }

    /// Mention a file: inserts @ and focuses the composer.
    func mentionFile() {
        if store.draft.isEmpty {
            store.draft = "@"
        } else if store.draft.hasSuffix(" ") || store.draft.hasSuffix("\n") {
            store.draft += "@"
        } else {
            store.draft += " @"
        }
        focused = true
    }

    /// Pasted images attach; pasted text keeps the default text behavior.
    func handlePastedItems(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                data, _ in
                guard let data else { return }
                Task { @MainActor in
                    attachImageData(data, fileName: "pasted-\(UUID().uuidString.prefix(8)).jpg")
                }
            }
        }
    }

    /// The pill row above the text field: thumbnails/file pills with remove "x";
    /// progress ring while uploading; retry on failure.
    @ViewBuilder var attachmentTray: some View {
        if !trayItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trayItems) { item in
                        ComposerAttachmentPill(
                            item: item,
                            uploadProgress: store.uploads.progress,
                            onRemove: {
                                attachmentStore.remove(item.id, from: store.agentId, store: store)
                            },
                            onRetry: {
                                attachmentStore.retry(item.id, in: store.agentId, store: store)
                            },
                            onTapImage: { image in attachmentViewerImage = image })
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 1)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Forge issue/PR (M12)

    /// The workspace's forge, from the checkout's PR status (upstream getForgePresentation
    /// source). Unknown or absent forges read as GitHub, like old daemons.
    var forgeId: String {
        guard let workspaceId = store.agent?.workspaceId,
            let workspace = session.workspaceDirectory.workspace(id: workspaceId)
        else { return "github" }
        let forge = session.checkout(for: workspace).prStatus?.forge?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return forge.isEmpty ? "github" : forge
    }

    var forgeIsGitLab: Bool { forgeId.lowercased() == "gitlab" }

    /// The forge items already in the tray, by picker row id (kind:number).
    var selectedForgeIds: [String] {
        trayItems.compactMap { item in
            guard case .attached(let attachment) = item.phase else { return nil }
            switch attachment {
            case .forgeChangeRequest(let forge): "change_request:\(forge.number)"
            case .forgeIssue(let forge): "issue:\(forge.number)"
            default: nil
            }
        }
    }

    /// Toggles one picker row into the tray (upstream toggleForgeAttachment): picking an
    /// attached row removes it.
    func toggleForgeAttachment(_ item: ForgeSearchItem) {
        if let existing = trayItems.first(where: { candidate in
            guard case .attached(let attachment) = candidate.phase else { return false }
            switch (attachment, item.kind) {
            case (.forgeChangeRequest(let forge), .changeRequest): forge.number == item.number
            case (.forgeIssue(let forge), .issue): forge.number == item.number
            default: false
            }
        }) {
            attachmentStore.remove(existing.id, from: store.agentId, store: store)
            return
        }
        guard let attachment = item.asAttachment else { return }
        attachmentStore.addForge(attachment, to: store.agentId, store: store)
    }

}
#endif
