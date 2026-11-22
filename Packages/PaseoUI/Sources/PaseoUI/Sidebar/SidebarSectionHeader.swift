#if canImport(UIKit)
import SwiftUI

/// A quiet section title in the directory ("Pinned").
struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.paseo(.footnote, weight: .medium))
            .foregroundStyle(Palette.secondaryInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
