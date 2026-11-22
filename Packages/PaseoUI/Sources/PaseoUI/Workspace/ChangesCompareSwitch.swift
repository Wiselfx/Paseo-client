#if canImport(UIKit)
import SwiftUI

/// Chip-style Uncommitted / vs base switch; only offered when the status carries a base ref.
struct ChangesCompareSwitch: View {
    @Binding var compare: ChangesCompare
    let baseRef: String?

    var body: some View {
        HStack(spacing: 2) {
            segment(.uncommitted, label: "Uncommitted")
            segment(.base, label: baseRef.map { "vs \($0)" } ?? "vs base")
        }
        .padding(.horizontal, Space.xs)
        .background(Palette.chip, in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segment(_ value: ChangesCompare, label: String) -> some View {
        let selected = compare == value
        return Button {
            guard compare != value else { return }
            compare = value
        } label: {
            // A 36 pt pill in a 44 pt track: the whole track height takes the tap.
            Text(label)
                .font(.paseo(.footnote, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Palette.background : Palette.secondaryInk)
                .background(selected ? Palette.ink : Color.clear, in: .capsule)
                .padding(.vertical, Space.xs)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Selected" : "")
    }
}
#endif
