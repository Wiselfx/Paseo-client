#if canImport(UIKit)
import SwiftUI

/// The editor's cadence presets: two columns, or one at accessibility text sizes. A tap selects
/// the preset and writes its expression into the cron field.
struct CadencePresetGrid: View {
    @Binding var usePreset: Int?
    @Binding var cron: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.sm) {
            ForEach(CadencePreset.all.enumerated(), id: \.element.expression) { index, preset in
                let selected = usePreset == index && cron == preset.expression
                Button {
                    usePreset = index
                    cron = preset.expression
                } label: {
                    Text(preset.label)
                        .font(.paseo(.caption, weight: .medium))
                        .foregroundStyle(selected ? Palette.background : Palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            selected ? Palette.ink : Palette.chip,
                            in: .rect(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .paseoFeedback(.selection, trigger: usePreset) { _, new in new != nil }
    }
}
#endif
