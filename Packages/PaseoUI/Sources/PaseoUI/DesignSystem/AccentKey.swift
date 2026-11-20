#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The SwiftUI side of the trait: `RootView` sets `\.accent`, and SwiftUI bridges it into the
/// UIKit trait collections its hosting views see.
struct AccentKey: EnvironmentKey {
    static let defaultValue = ClaudeAccent.paseo
}
extension AccentKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> ClaudeAccent {
        traitCollection.accent
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: ClaudeAccent) {
        mutableTraits[AccentTrait.self] = value
    }
}
#endif
