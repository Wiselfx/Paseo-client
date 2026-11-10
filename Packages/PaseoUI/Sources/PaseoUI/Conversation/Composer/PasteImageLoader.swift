#if canImport(UIKit)
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Reads every image on the pasteboard (D2 §2). `UIPasteboard.general.image` only ever returns the
/// first one, so the field and the `+` menu both come through here, one `itemProvider` at a time,
/// and the system loads the bytes off the main thread.
enum PasteImageLoader {
    /// The representations a pasted image may be registered under, in the order a screenshot, a
    /// photo and a copied web image usually provide them.
    static let imageTypes: [UTType] = [.image, .png, .jpeg]

    /// Every image on the pasteboard, in pasteboard order. Empty when there are none.
    @MainActor
    static func loadAll() async -> [Data] {
        let providers = UIPasteboard.general.itemProviders
        var images: [Data] = []
        for provider in providers {
            for type in imageTypes
            where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                // `loadDataRepresentation(for:)` is the iOS 16 API; the identifier-based one
                // returns `Progress` and has no async form.
                if let data = try? await provider.loadDataRepresentation(for: type) {
                    images.append(data)
                    break
                }
            }
        }
        return images
    }
}
#endif
