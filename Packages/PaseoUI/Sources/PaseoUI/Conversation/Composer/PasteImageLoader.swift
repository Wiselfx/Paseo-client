#if canImport(UIKit)
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Reads every image on the pasteboard (D2 §2). `UIPasteboard.general.image` only ever returns the
/// first one, so the field and the `+` menu both come through here, one `itemProvider` at a time,
/// and the bytes are loaded by the system off the main thread.
enum PasteImageLoader {
    /// The representations a pasted image may be registered under, in the order a screenshot, a
    /// photo and a copied web image usually provide them.
    static let imageTypes = [
        UTType.image.identifier, UTType.png.identifier, UTType.jpeg.identifier,
    ]

    /// Every image on the pasteboard, in pasteboard order. Empty when there are none.
    @MainActor
    static func loadAll() async -> [Data] {
        let providers = UIPasteboard.general.itemProviders
        var images: [Data] = []
        for provider in providers {
            for identifier in imageTypes
            where provider.hasItemConformingToTypeIdentifier(identifier) {
                if let data = try? await provider.loadDataRepresentation(
                    forTypeIdentifier: identifier)
                {
                    images.append(data)
                    break
                }
            }
        }
        return images
    }
}
#endif
