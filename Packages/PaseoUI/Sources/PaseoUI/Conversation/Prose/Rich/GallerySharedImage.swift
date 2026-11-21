#if canImport(UIKit)
import SwiftUI
import UIKit

/// One image offered to the share sheet, `Identifiable` so the gallery presents it with
/// `.sheet(item:)` instead of a hand-built `Binding<Bool>` over an optional.
struct GallerySharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif
