import PaseoUI
import SwiftUI
import UIKit

extension UIUserInterfaceStyle {
    /// The window style for an Appearance choice. `.unspecified` is "System": the only value
    /// that really returns to following the OS. Derived from `ClaudeAppearance.colorScheme` so the
    /// app has one statement of which scheme each choice is (Pure black is a dark scheme).
    init(_ appearance: ClaudeAppearance) {
        switch appearance.colorScheme {
        case .some(.light): self = .light
        case .some: self = .dark
        case nil: self = .unspecified
        }
    }
}
