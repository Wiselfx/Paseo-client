#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The SwiftUI side of the trait: `RootView` sets `\.pureBlack`, and SwiftUI bridges it into the
/// UIKit trait collections its hosting views see.
struct PureBlackKey: EnvironmentKey {
    static let defaultValue = false
}
extension PureBlackKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> Bool {
        traitCollection.pureBlack
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: Bool) {
        mutableTraits[PureBlackTrait.self] = value
    }
}
#endif
