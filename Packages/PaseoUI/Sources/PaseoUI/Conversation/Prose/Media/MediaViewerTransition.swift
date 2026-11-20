#if canImport(UIKit)
import SwiftUI
import UIKit
import VisionKit

/// The cover transition: zoom from the exact thumbnail, or the system default under
/// Reduce Motion. A modifier (not a ternary): the two transition types do not mix.
/// Shared with the artifact page, which enters the same way.
struct MediaViewerTransition: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
    }
}
#endif
