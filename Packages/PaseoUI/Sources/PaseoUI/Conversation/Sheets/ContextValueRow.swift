#if canImport(UIKit)
import SwiftUI

/// One label and value line in the context sheet's grouped rows.
struct ContextValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.paseo(.body))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            Text(value)
                .monospacedDigit()
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.lg)
        // `minHeight`, not `height`: a value row is a text container, and at the largest Dynamic
        // Type sizes a fixed 44 clips the value instead of growing the row.
        .frame(minHeight: 44)
    }
}
#endif
