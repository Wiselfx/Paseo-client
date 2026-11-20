#if canImport(UIKit)
import Foundation
import SwiftUI

/// The hero's once-per-launch state (E2b §1): one greeting draw and one rise entrance for the
/// whole process, never persisted. The greeting lives in a `static let`; the rise needs a flag
/// because the first hero claims it and every later instance appears settled. A lock keeps the
/// flag safe because SwiftUI may build a value from a nonisolated context.
final class HomeHeroLaunchState: @unchecked Sendable {
    static let shared = HomeHeroLaunchState()

    private let lock = NSLock()
    private var rose = false

    /// Whether an earlier hero of this launch already played the rise.
    var hasRisen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rose
    }

    /// True for exactly one caller: the first hero of the launch.
    func claimRise() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !rose else { return false }
        rose = true
        return true
    }
}
#endif
