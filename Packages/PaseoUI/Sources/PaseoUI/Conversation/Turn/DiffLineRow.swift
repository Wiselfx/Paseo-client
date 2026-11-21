#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One diff line, tinted by its kind. `wrap` lets a long line wrap instead of scrolling sideways.
struct DiffLineRow: View {
    let line: ClaudeDiffLine
    let wrap: Bool

    var body: some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.paseo(.codeSmall))
            .foregroundStyle(line.kind == .header ? Palette.tertiaryInk : Palette.ink)
            .fixedSize(horizontal: !wrap, vertical: true)
            .padding(.horizontal, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
    }

    private var background: Color {
        switch line.kind {
        case .added: Palette.diffAdded
        case .removed: Palette.diffRemoved
        case .context, .header: .clear
        }
    }
}
#endif
