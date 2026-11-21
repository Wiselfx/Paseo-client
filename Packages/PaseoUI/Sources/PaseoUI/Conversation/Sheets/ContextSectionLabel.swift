#if canImport(UIKit)
import SwiftUI

/// The small heading above a group on the context sheet.
struct ContextSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
            .padding(.bottom, -Space.xs)
    }
}
#endif
