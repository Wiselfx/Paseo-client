#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One provider subagent in the subagents sheet: status dot, title and subtitle, status word.
/// Read-only; tapping opens its timeline through `onOpen`.
struct ProviderSubagentRow: View {
    let item: ProviderSubagent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Space.md) {
                Circle()
                    .fill(SubagentStatusWord.dot(item.status))
                    .frame(width: 8, height: 8)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.paseo(.callout, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.sm)
                Text(SubagentStatusWord.label(item.status))
                    .font(.paseo(.caption))
                    .foregroundStyle(Palette.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.glyph(.small, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryInk)
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(SubagentStatusWord.label(item.status))")
    }

    private var title: String {
        item.title ?? item.description ?? item.provider
    }

    private var subtitle: String? {
        if item.title != nil {
            return item.description ?? item.subtitle
        }
        return item.subtitle
    }
}
#endif
