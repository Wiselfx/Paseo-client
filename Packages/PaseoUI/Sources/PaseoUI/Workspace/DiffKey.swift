#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

// MARK: - Diff key

struct DiffKey: Hashable {
    let path: String
    let signature: String
    let hideWhitespace: Bool
}
#endif
