#if canImport(UIKit)
import SwiftUI

/// The trailing accessory of a `ListRow`.
struct ListRowAccessoryView: View {
    let accessory: ListRow.Accessory

    var body: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
                .accessibilityHidden(true)
        case .disclosure(let text):
            HStack(spacing: Space.sm) {
                if let text {
                    Text(text)
                        .font(.paseo(.callout))
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
                    .accessibilityHidden(true)
            }
        case .checkmark(let isOn):
            if isOn {
                Image(systemName: "checkmark")
                    .font(.glyph(.regular, weight: .semibold))
                    .foregroundStyle(Palette.selection)
                    .accessibilityHidden(true)
            }
        case .value(let text):
            Text(text)
                .font(.paseo(.callout))
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
        case .toggle(let isOn):
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Palette.toggleTint)
        case .badge(let text):
            StatePill(text, tone: .neutral)
        case .progress:
            InlineProgress()
        }
    }
}
#endif
