#if canImport(UIKit)
import SwiftUI
import UIKit

/// The one sheet an `ArtifactPage` can have up at a time, presented with `.sheet(item:)`: the
/// share sheet for the card's image or the exported `.html`, or an in-app Safari for a link a
/// file preview followed. One optional replaces three `Binding<Bool>`s built over optionals.
enum ArtifactPageSheet: Identifiable {
    case shareImage(UIImage)
    case shareFile(URL)
    case safari(URL)

    var id: String {
        switch self {
        case .shareImage: "share-image"
        case .shareFile(let url): "share-file:\(url.absoluteString)"
        case .safari(let url): "safari:\(url.absoluteString)"
        }
    }
}
#endif
