#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// Up to two chips, then "+N". Low emphasis; reading priority sits with the branch and
/// status, labels come after them.
struct WorkspaceLabelChips: View {
    let definitions: [WorkspaceLabelDefinition]

    var body: some View {
        if !definitions.isEmpty {
            let shown = Array(definitions.prefix(2))
            HStack(spacing: 4) {
                ForEach(shown, id: \.name) { label in
                    WorkspaceLabelChip(label: label)
                }
                if definitions.count > shown.count {
                    let extra = definitions.count - shown.count
                    Text("+\(PaseoFormat.integer(extra))")
                        .font(.paseo(.caption2, weight: .medium))
                        .foregroundStyle(Palette.captionInk)
                        .accessibilityLabel("\(extra) more labels")
                }
            }
        }
    }
}
#endif
