#if canImport(UIKit)
import SwiftUI

/// A line number in a code gutter. The gutter's width is measured from the widest number set in
/// the same font, so it grows with Dynamic Type and the code size step instead of truncating a
/// fixed width.
struct CodeLineNumber: View {
    let number: Int
    /// Digits of the widest number in the gutter (at least two, so short files keep a steady
    /// gutter).
    let digits: Int
    let font: Font

    var body: some View {
        Text(verbatim: String(repeating: "8", count: digits))
            .hidden()
            .overlay(alignment: .trailing) {
                Text(verbatim: String(number))
                    .foregroundStyle(Palette.captionInk)
            }
            .font(font)
            .monospacedDigit()
    }
}
#endif
