#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

// MARK: - Render values

struct DiffRender: Sendable {
    let sections: [DiffSection]
    let totalWidth: CGFloat
    let gutterWidth: CGFloat
}
#endif
