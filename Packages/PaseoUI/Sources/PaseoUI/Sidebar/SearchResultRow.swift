#if canImport(UIKit)
import SwiftUI
import UIKit

/// One result in the command center: leading dot or symbol, title and subtitle, trailing badge.
/// Its own view, so each row is a separate node in the results list. `action` is a closure, which
/// SwiftUI cannot compare, so a row re-runs whenever the list does; `isSelected` is the only value
/// that moves with the keyboard highlight.
struct SearchResultRow: View {
    let row: SearchModel.Result
    let isSelected: Bool
    /// The Switch host action's chevron.
    let hostExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.paseo(.callout, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(row.kind == .file ? .paseo(.codeCaption) : .paseo(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: Space.sm)
                trailing
            }
            .padding(.horizontal, Space.lg)
            .frame(minHeight: 44)
            .background(
                isSelected ? Palette.chip : Color.clear, in: .rect(cornerRadius: Radius.md))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Space.md)
        .accessibilityIdentifier("search.row.\(row.id)")
    }

    @ViewBuilder private var leading: some View {
        if let dot = row.dot {
            StatusDot(dot)
        } else if let symbol = row.symbol {
            Image(systemName: symbol)
                .font(.glyph(.regular))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 22)
        } else {
            Color.clear.frame(width: 22)
        }
    }

    @ViewBuilder private var trailing: some View {
        if row.archived {
            Text("Archived")
                .font(.paseo(.caption2, weight: .medium))
                .foregroundStyle(Palette.captionInk)
                .padding(.horizontal, Space.sm)
                .frame(minHeight: 20)
                .background(Palette.chip, in: .rect(cornerRadius: Radius.xs))
        } else if row.kind == .action, row.action == .switchHost {
            Image(systemName: hostExpanded ? "chevron.up" : "chevron.down")
                .font(.glyph(.small, weight: .semibold))
                .foregroundStyle(Palette.tertiaryInk)
        } else {
            Color.clear
        }
    }
}
#endif
