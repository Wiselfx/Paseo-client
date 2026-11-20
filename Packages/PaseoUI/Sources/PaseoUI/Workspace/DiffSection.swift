#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

struct DiffSection: Identifiable, Sendable {
    let hunk: Int
    let header: String
    let rows: [DiffModel.Row]

    var id: Int { hunk }
}
#endif
