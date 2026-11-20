#if canImport(UIKit)
import SwiftUI

/// A `Section` header inside a `PageList`: sentence case, footnote semibold, `secondaryInk`,
/// flush with the row text. The list owns the vertical rhythm, the row owns the leading edge.
struct PageSectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.lg)
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
