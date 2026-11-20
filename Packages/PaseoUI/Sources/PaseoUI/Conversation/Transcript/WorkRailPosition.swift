#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Whether the rail runs into a step from above and on from it below.
struct WorkRailPosition: Equatable, Sendable {
    var above: Bool
    var below: Bool
}
#endif
