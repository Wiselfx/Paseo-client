#if canImport(UIKit)
import SwiftUI

/// A grouped block of rows: the panel fill at `Radius.group`, with `RowDivider` between rows.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .background(Palette.panel, in: .rect(cornerRadius: Radius.group))
    }
}

/// The hairline between two rows in a group, inset by the row's own leading padding.
struct RowDivider: View {
    var body: some View {
        ClaudeDivider().padding(.horizontal, Space.lg)
    }
}

#Preview("Light") {
    VStack(spacing: Space.lg) {
        RowGroup {
            ListRow(title: "First row", systemImage: "person", accessory: .chevron, action: {})
            RowDivider()
            ListRow(title: "Second row", systemImage: "folder", action: {})
        }
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    RowGroup {
        ListRow(title: "First row", systemImage: "person", accessory: .chevron, action: {})
        RowDivider()
        ListRow(title: "Second row", systemImage: "folder", action: {})
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
