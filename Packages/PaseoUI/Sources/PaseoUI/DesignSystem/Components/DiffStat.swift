#if canImport(UIKit)
import SwiftUI

/// `+N −N` in mono digits, each side hidden at zero.
struct DiffStat: View {
    private let added: Int
    private let removed: Int
    /// Tight spots (a sidebar row's meta line) read `+134k`; detail panes keep the exact count.
    private let compact: Bool

    init(added: Int, removed: Int, compact: Bool = false) {
        self.added = added
        self.removed = removed
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if added > 0 {
                Text("+\(count(added))")
                    .foregroundStyle(Palette.diffAddedInk)
            }
            if removed > 0 {
                Text("−\(count(removed))")
                    .foregroundStyle(Palette.diffRemovedInk)
            }
        }
        .font(.paseo(.codeSmall))
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func count(_ value: Int) -> String {
        compact ? PaseoFormat.compactCount(value) : PaseoFormat.integer(value)
    }
}

#Preview("Light") {
    VStack(alignment: .leading, spacing: Space.sm) {
        DiffStat(added: 12, removed: 3)
        DiffStat(added: 0, removed: 1204)
        DiffStat(added: 7, removed: 0)
        DiffStat(added: 0, removed: 0)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Compact") {
    VStack(alignment: .leading, spacing: Space.sm) {
        DiffStat(added: 133_900, removed: 18_800, compact: true)
        DiffStat(added: 12, removed: 3, compact: true)
        DiffStat(added: 0, removed: 1_250, compact: true)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
