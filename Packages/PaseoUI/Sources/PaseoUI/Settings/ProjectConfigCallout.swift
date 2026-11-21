#if canImport(UIKit)
import SwiftUI

/// A failure card on the project page: what happened, why, and one action.
struct ProjectConfigCallout: View {
    let title: String
    let detail: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(.paseo(.callout, weight: .semibold))
                .foregroundStyle(Palette.failureInk)
            Text(detail)
                .font(.paseo(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                ProjectChip(horizontalPadding: Space.lg, visibleHeight: 34) {
                    Text(actionLabel)
                        .font(.paseo(.footnote, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(Palette.quoteWash, in: .rect(cornerRadius: Radius.lg))
    }
}
#endif
