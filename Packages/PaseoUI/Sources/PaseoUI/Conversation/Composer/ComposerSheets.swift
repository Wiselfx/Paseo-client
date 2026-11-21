#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Composer modals and voice

/// The composer's sheets and covers: the file importer, the forge picker, the camera, and the
/// attachment viewer. R4 owns the sheet bodies.
struct ComposerSheets: ViewModifier {
    let controller: ChatController?
    let store: ConversationStore?
    @Binding var showFileImporter: Bool
    @Binding var showForgePicker: Bool
    @Binding var showCameraPicker: Bool
    @Binding var viewedImage: ViewedAttachmentImage?
    let forgeIsGitLab: Bool
    let onFileURLs: ([URL]) -> Void
    /// A failed file import, said where the composer's mode says its errors (a toast in a
    /// conversation, the line under the field in a draft).
    let onFileImportError: (String) -> Void
    /// The captured frame as it came from the camera: encoding it is the receiver's job, off the
    /// main actor (`ComposerImageProcessor.jpegData(of:)`).
    let onCameraImage: (UIImage) -> Void
    let onForgePick: (ForgeSearchItem) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showFileImporter, allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): onFileURLs(urls)
                case .failure(let error): onFileImportError(error.localizedDescription)
                }
            }
            .sheet(isPresented: $showForgePicker) {
                if let controller {
                    ForgeSearchPicker(
                        session: controller.session, cwd: store?.agent?.cwd ?? "",
                        isMergeRequest: forgeIsGitLab,
                        onPick: { item in onForgePick(item) },
                        selectedIds: selectedIds)
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraCaptureView(
                    onCapture: { image in
                        showCameraPicker = false
                        onCameraImage(image)
                    },
                    onCancel: { showCameraPicker = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $viewedImage) { viewed in
                AttachmentImageViewer(image: viewed.image)
            }
    }

    private var selectedIds: [String] {
        guard let controller, let store else { return [] }
        return controller.attachmentStore.items(for: store.agentId).compactMap { item in
            guard case .attached(let attachment) = item.phase else { return nil }
            return switch attachment {
            case .forgeChangeRequest(let forge): "change_request:\(forge.number)"
            case .forgeIssue(let forge): "issue:\(forge.number)"
            default: nil
            }
        }
    }
}
#endif
