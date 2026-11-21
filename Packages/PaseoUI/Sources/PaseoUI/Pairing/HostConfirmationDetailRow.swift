#if canImport(UIKit)
import SwiftUI

/// One label and value row of the host confirmation. The value is what the user must check
/// before trusting a host, so it wraps below the label rather than truncating when it does not
/// fit beside it (large Dynamic Type, narrow widths).
struct HostConfirmationDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.paseo(.callout))
                Spacer(minLength: 8)
                valueText
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label)
                    .font(.paseo(.callout))
                valueText
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Space.sm)
        .frame(minHeight: 52, alignment: .leading)
    }

    private var valueText: some View {
        Text(value)
            .font(.paseo(.code))
            .foregroundStyle(Palette.secondaryInk)
            .textSelection(.enabled)
    }
}
#endif
