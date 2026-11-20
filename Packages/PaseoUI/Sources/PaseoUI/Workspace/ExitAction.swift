#if canImport(UIKit)
import Foundation
import ImageIO
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ExitAction: Identifiable {
    case leave
    case cancelEditing

    var id: Int {
        switch self {
        case .leave: 0
        case .cancelEditing: 1
        }
    }
}
#endif
