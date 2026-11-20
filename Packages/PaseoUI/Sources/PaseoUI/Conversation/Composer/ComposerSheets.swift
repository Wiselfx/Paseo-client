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
    @Binding var attachmentViewerImage: UIImage?
    let forgeIsGitLab: Bool
    let onFileURLs: ([URL]) -> Void
    let onCameraImage: (Data) -> Void
    let onForgePick: (ForgeSearchItem) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showFileImporter, allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls): onFileURLs(urls)
                case .failure(let error): controller?.showToast(error.localizedDescription)
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
                        guard let data = image.jpegData(compressionQuality: 1.0) else {
                            controller?.showToast("Couldn't read that photo.")
                            return
                        }
                        onCameraImage(data)
                    },
                    onCancel: { showCameraPicker = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { attachmentViewerImage != nil },
                    set: { if !$0 { attachmentViewerImage = nil } })
            ) {
                if let image = attachmentViewerImage {
                    AttachmentImageViewer(image: image)
                }
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
