#if canImport(UIKit)
import SwiftUI

/// A settings or sidebar section label: sentence case, 13 pt semibold, `secondaryInk`.
struct SectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .semibold))
            .foregroundStyle(Palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.lg)
            .padding(.bottom, Space.sm)
            .padding(.top, Space.xl)
    }
}

#Preview("Light") {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Appearance")
        SectionHeader("Fonts")
    }
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(alignment: .leading, spacing: 0) {
        SectionHeader("Appearance")
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
