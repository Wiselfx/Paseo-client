#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// The user's scrollback preference (Settings → Terminal): how many lines SwiftTerm keeps.
/// `UserDefaults` has no typed integer present when never set — `integer(forKey:)` returns 0,
/// which maps to the 2,000-line default.
enum PaseoTerminalScrollback {
    static let storageKey = "paseo.terminal.scrollback"
    static let defaultValue = 2_000

    static func current(_ defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: storageKey)
        return value > 0 ? value : defaultValue
    }
}
#endif
