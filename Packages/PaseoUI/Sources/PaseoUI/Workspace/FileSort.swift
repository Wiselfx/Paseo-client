#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The list ordering keys. Folders always come first regardless of key.
enum FileSort: String, CaseIterable {
    case name, modified, size

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Modified"
        case .size: "Size"
        }
    }
}
#endif
