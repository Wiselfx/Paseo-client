#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// One swatch in the ten-color palette rows.
struct LabelColorSwatch: View {
    let color: WorkspaceLabelColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(labelFill(color))
                .frame(width: 22, height: 22)
                .overlay {
                    if selected {
                        Circle()
                            .stroke(Palette.ink, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(color.rawValue)")
        .accessibilityValue(selected ? "Selected" : "")
    }
}
#endif
