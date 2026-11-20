#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The colour accent as a UIKit trait, exactly like `PureBlackTrait`: the accent tokens are
/// dynamic `UIColor` providers that read it, so a switch redraws in place — no rebuild and no
/// `@AppStorage` read in any leaf body.
struct AccentTrait: UITraitDefinition {
    static let defaultValue = ClaudeAccent.paseo
    static let identifier = "com.wiselfx.paseoclient.accent"
}
#endif
