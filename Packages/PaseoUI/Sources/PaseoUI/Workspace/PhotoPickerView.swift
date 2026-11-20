#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// PHPicker wrapper (iOS 14+, no library-permission prompt for `.images`): one image, its
/// original bytes, file name from the content type. SwiftUI's own `.photosPicker` modifier is
/// avoided because availability varies across SDKs.
struct PhotoPickerView: UIViewControllerRepresentable {
    var onPick: @MainActor (Data, String, String) -> Void
    var onCancel: @MainActor () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: @MainActor (Data, String, String) -> Void
        let onCancel: @MainActor () -> Void

        init(
            onPick: @escaping @MainActor (Data, String, String) -> Void,
            onCancel: @escaping @MainActor () -> Void
        ) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                Task { @MainActor in onCancel() }
                return
            }
            let provider = result.itemProvider
            let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [onPick, onCancel] data, _ in
                let ext = type.preferredFilenameExtension ?? "jpg"
                let mime = type.preferredMIMEType ?? "image/jpeg"
                if let data {
                    Task { @MainActor in onPick(data, "photo.\(ext)", mime) }
                } else {
                    Task { @MainActor in onCancel() }
                }
            }
        }
    }
}
#endif
