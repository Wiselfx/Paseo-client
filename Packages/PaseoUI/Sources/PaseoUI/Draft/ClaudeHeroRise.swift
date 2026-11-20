#if canImport(UIKit)
import Foundation
import SwiftUI

struct ClaudeHeroRise: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: reduceMotion || visible ? 0 : ClaudeMotion.riseDistance)
            .blur(radius: reduceMotion || visible ? 0 : ClaudeMotion.enterBlur)
    }
}
#endif
