#if canImport(UIKit)
import SwiftUI

/// A sheet's detent policy: the one place a sheet names its detents, drag indicator and
/// background (PLAN §RA2, §RE).
enum SheetDetents: Sendable {
    case large
    case mediumLarge
    case medium

    var presentationDetents: Set<PresentationDetent> {
        switch self {
        case .large: [.large]
        case .mediumLarge: [.medium, .large]
        case .medium: [.medium]
        }
    }

    var dragIndicator: Visibility {
        switch self {
        case .large: .hidden
        case .mediumLarge, .medium: .visible
        }
    }
}
#endif
