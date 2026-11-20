#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// The chip on the row meta line: the name in its identity foreground on its own 10% tint.
struct WorkspaceLabelChip: View {
    let label: WorkspaceLabelDefinition

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label.name)
            .font(.paseo(.caption2, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(labelForeground(label.color, scheme: colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(labelGround(label.color), in: .capsule)
            .accessibilityLabel("Label: \(label.name)")
    }
}
#endif
