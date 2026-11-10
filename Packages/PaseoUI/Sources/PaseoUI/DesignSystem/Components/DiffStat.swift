#if canImport(UIKit)
import SwiftUI

/// `+N −N` in mono digits, each side hidden at zero.
struct DiffStat: View {
    private let added: Int
    private let removed: Int

    init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if added > 0 {
                Text("+\(PaseoFormat.integer(added))")
                    .foregroundStyle(Palette.diffAddedInk)
            }
            if removed > 0 {
                Text("−\(PaseoFormat.integer(removed))")
                    .foregroundStyle(Palette.diffRemovedInk)
            }
        }
        .font(.paseo(.codeSmall))
        .accessibilityElement(children: .combine)
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

#Preview("Dark") {
    VStack(alignment: .leading, spacing: Space.sm) {
        DiffStat(added: 12, removed: 3)
        DiffStat(added: 119_900, removed: 0)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
