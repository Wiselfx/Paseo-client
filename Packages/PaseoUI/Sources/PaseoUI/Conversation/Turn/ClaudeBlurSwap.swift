#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The swap the line trades wordings by: old words leave upward through a 2 pt blur, new words
/// enter from below, 150 ms ease-in-out with an 8 pt travel.
@Animatable
struct ClaudeBlurSwap: ViewModifier {
    var blur: Double
    var y: Double
    var alpha: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: y).opacity(alpha)
    }
}
#endif
