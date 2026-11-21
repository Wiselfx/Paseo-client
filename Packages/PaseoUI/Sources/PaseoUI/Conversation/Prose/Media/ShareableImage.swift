#if canImport(UIKit)
import UIKit

/// An image waiting in the viewer's share sheet. `UIImage` is not `Identifiable`, and
/// `sheet(item:)` presents and clears from one optional value, so the sheet cannot open empty.
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif
