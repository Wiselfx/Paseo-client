#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// One prompt in the "Jump to message" sheet: its number, the first line of it, and a checkmark
/// on the message that is on screen.
struct ChatTurnNavRow: View {
    /// 1-based position in the conversation.
    let number: Int
    let item: ChatOutlineItem
    let isCurrent: Bool
    let onSelect: () -> Void

    @ScaledMetric(relativeTo: .callout) private var badge: CGFloat = 32

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(PaseoFormat.integer(number))
                    .font(.paseo(.codeSmall, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.secondaryInk)
                    .frame(minWidth: badge, minHeight: badge)
                    .background(isCurrent ? Palette.ink.opacity(0.10) : .clear, in: .circle)
                Text(item.preview)
                    .font(.paseo(.callout))
                    .foregroundStyle(isCurrent ? Palette.ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.glyph(.small, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("turnNav.\(number)")
        // The preview is what tells the rows apart, so it stays in the spoken label.
        .accessibilityLabel("Message \(number): \(item.preview)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
#endif
