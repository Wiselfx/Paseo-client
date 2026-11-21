#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// A footer control: a 28 pt glyph in a 44 pt tap target, or a small spinner where the glyph was
/// while work runs.
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
        .frame(width: 44, height: 44)
        .contentShape(.rect)
    }
}
#endif
