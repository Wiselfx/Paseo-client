#if canImport(UIKit)
import Foundation
import Observation
import PaseoStore
import SwiftUI
import UIKit

struct FileViewerTarget: Identifiable {
    let checkout: CheckoutStore
    let relPath: String
    var id: String { relPath }
}
#endif
