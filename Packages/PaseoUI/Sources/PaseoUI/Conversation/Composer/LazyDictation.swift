#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Builds a `DictationController` when first asked.
@MainActor
final class LazyDictation {
    lazy var controller = DictationController()
}
extension View {
    func composerCardChrome(expanded: Bool) -> some View {
        modifier(ComposerCardChrome(expanded: expanded))
    }
}
#endif
