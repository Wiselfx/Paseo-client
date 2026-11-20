#if canImport(UIKit)
import SwiftUI
import Synchronization
import UIKit

/// SF Symbol sizes. Icons are not text roles.
enum GlyphSize: Hashable, Sendable {
    case small  // 13
    case regular  // 17
    case large  // 20
    case xlarge  // 28
    case hero  // 34

    var size: CGFloat {
        switch self {
        case .small: 13
        case .regular: 17
        case .large: 20
        case .xlarge: 28
        case .hero: 34
        }
    }
}
#endif
