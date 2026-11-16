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
                if let data = await load(type.identifier, from: provider) {
                    images.append(data)
                    break
                }
            }
        }
        return images
    }

    /// Both `loadDataRepresentation` forms return `Progress`, so neither has an async overload;
    /// bridge the completion handler, which the system calls on a background queue.
    nonisolated private static func load(_ identifier: String, from provider: NSItemProvider) async -> Data? {
        nonisolated(unsafe) let provider = provider
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
#endif
