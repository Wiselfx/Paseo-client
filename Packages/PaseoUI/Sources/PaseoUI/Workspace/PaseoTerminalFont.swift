#if canImport(UIKit)
import PaseoStore
import QuartzCore
import SwiftTerm
import SwiftUI
import UIKit

/// The terminal's mono font. The base is 13 pt, scaled by the Settings → General → Code size
/// step (`ClaudeTextScale.codeMultiplier()`, the same multiplier `Typography`
/// applies to code text elsewhere), so the terminal follows the user's code-size choice.
enum PaseoTerminalFont {
    static let baseSize: CGFloat = 13

    static func size() -> CGFloat {
        baseSize * ClaudeTextScale.codeMultiplier()
    }

    static func current() -> UIFont {
        UIFont.monospacedSystemFont(ofSize: size(), weight: .regular)
    }
}
#endif
