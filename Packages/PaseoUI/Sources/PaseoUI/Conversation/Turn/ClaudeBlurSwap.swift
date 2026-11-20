#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The swap the line trades wordings by: old words leave upward through a 2 pt blur, new words
/// enter from below, 150 ms ease-in-out with an 8 pt travel.
struct ClaudeBlurSwap: ViewModifier {
    var blur: CGFloat
    var y: CGFloat
    var alpha: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(blur, AnimatablePair(y, alpha)) }
        set {
            blur = newValue.first
            y = newValue.second.first
            alpha = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: y).opacity(alpha)
    }
}
#endif
