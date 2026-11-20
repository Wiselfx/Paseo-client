#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit
import WebKit

/// Applies the zoom source only when the shared namespace is present (previews have
/// none, and degrade to the default cover transition).
struct ArtifactZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}
#endif
