#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A 28 pt footer control: the glyph, or a small spinner where the glyph was while work runs.
struct ClaudeTurnActionGlyph: View {
    var systemImage: String
    var busy: Bool

    var body: some View {
        Group {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.glyph(.regular, weight: .light))
                    .foregroundStyle(Palette.tertiaryInk)
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(.rect)
    }
}

/// "2 thoughts, 1 tool call": the counted header, then a transparent card of rows, each opening on
/// its own. The card is capped at `min(400 pt, 50% of height)` and scrolls inside.
#endif
