#if canImport(UIKit)
import UIKit

/// The attachment image the full-screen viewer is showing: `UIImage` is not `Identifiable`, so
/// `fullScreenCover(item:)` needs this wrapper, and each tap is a fresh presentation.
struct ViewedAttachmentImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif
