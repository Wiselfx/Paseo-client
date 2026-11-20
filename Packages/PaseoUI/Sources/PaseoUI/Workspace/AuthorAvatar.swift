#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

// MARK: - Small pieces

struct AuthorAvatar: View {
    let author: String

    var body: some View {
        Text(String(author.prefix(1)).uppercased())
            .font(.paseo(.footnote, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .frame(width: 28, height: 28)
            .background(Palette.chip, in: .circle)
            .accessibilityHidden(true)
    }
}
#endif
