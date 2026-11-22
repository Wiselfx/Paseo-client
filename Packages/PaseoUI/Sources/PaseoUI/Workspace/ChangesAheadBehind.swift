#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// "↑3 ↓1": commits ahead of and behind the upstream, each shown only when non-zero.
struct ChangesAheadBehind: View {
    let aheadBehind: CheckoutAheadBehind

    var body: some View {
        if aheadBehind.ahead > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up").font(.glyph(.small, weight: .semibold))
                Text("\(PaseoFormat.integer(aheadBehind.ahead))").font(.paseo(.codeSmall))
            }
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityLabel(Text("^[\(aheadBehind.ahead) commit](inflect: true) ahead"))
        }
        if aheadBehind.behind > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down").font(.glyph(.small, weight: .semibold))
                Text("\(PaseoFormat.integer(aheadBehind.behind))").font(.paseo(.codeSmall))
            }
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityLabel(Text("^[\(aheadBehind.behind) commit](inflect: true) behind"))
        }
    }
}
#endif
