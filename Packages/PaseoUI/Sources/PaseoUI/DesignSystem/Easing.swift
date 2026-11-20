#if canImport(UIKit)
import SwiftUI

/// The curves the loader needs, in one place.
enum Easing {
    /// Plain ease-in-out for the hand-over cross-fade.
    static func easeInOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped < 0.5 ? 2 * clamped * clamped : -1 + (4 - 2 * clamped) * clamped
    }
}
#endif
