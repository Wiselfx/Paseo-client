#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The tall draft's expand control, in the card's top-trailing corner (H3 §2).
///
/// It used to sit `.padding(.trailing, 104)` to the left — "the crab's spot" — although the
/// crab's 72 pt frame stands *above* the card, so the control floated a crab's width from the
/// corner it belongs to, over the first line of text, at whatever that literal happened to
/// make on the current model. The `1` on its top edge was the same kind of guess.
///
/// Now nothing is hard-coded except tokens: the 44 pt hit frame is flush with the card's
/// corner (it hangs `verticalInset` up into the card's padding, see `ComposerView.fieldRow`) and
/// its 28 pt circle lands `(hitSize − expandSize) / 2 = 8` pt inside, the same 8 pt the row's 36 pt
/// circles keep (E1 §4). The field gives back exactly that column while the control is shown
/// (`ComposerUITextView.applyTrailingInset`), so no glyph ever runs under it.
///
/// It can never meet the crab: the crab's feet are on the card's top edge and its 104 × 72 pt
/// frame is above it, while this control is inside the card — no width, type size, mode or
/// mascot state brings them together, so the crab does not have to move.
struct ComposerExpandButton: View {
    let isShown: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isShown {
            Button(action: action) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.glyph(.small, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(width: ComposerMetrics.expandSize, height: ComposerMetrics.expandSize)
                    .background(Palette.chip, in: .circle)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Expand composer")
            .transition(.opacity)
        }
    }
}
#endif
