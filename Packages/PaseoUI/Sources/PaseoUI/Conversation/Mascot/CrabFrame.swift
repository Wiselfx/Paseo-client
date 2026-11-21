#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import PaseoStore

/// One frame of the crab: the colour sprite with the ink mask tinted over it, placed at the
/// animation's window offset. It draws only, so the hit target lives outside the per-tick view.
struct CrabFrame: View {
    let animation: CrabAnimation
    let index: Int

    var body: some View {
        let frameSize = animation.displaySize
        let offset = animation.windowOffset
        ZStack {
            if let sprite = CrabSheetLoader.frame(animation: animation, index: index, ink: false) {
                Image(uiImage: sprite)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: frameSize.width, height: frameSize.height)
            }
            if let mask = CrabSheetLoader.frame(animation: animation, index: index, ink: true) {
                Image(uiImage: mask)
                    .resizable()
                    .interpolation(.none)
                    .renderingMode(.template)
                    .foregroundStyle(Palette.tertiaryInk)
                    .frame(width: frameSize.width, height: frameSize.height)
            }
        }
        .offset(x: offset.x, y: offset.y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
