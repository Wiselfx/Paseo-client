#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The pure-black flag as a UIKit trait: the palette's `UIColor` providers read it from the
/// trait collection, so switching Dark ↔ Pure black redraws live instead of rebuilding the app.
struct PureBlackTrait: UITraitDefinition {
    static let defaultValue = false
    static let identifier = "com.wiselfx.paseoclient.pureBlack"
}
#endif
