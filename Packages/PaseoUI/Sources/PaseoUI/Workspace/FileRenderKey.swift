#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Render model

struct FileRenderKey: Hashable {
    let path: String
    let revision: String
    let dark: Bool
    /// The viewer's pixel budget: a rotation re-decodes the image at the new size exactly once.
    let pixelBudget: Int
}
#endif
