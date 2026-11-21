#if canImport(UIKit)
import SwiftUI

/// The Preview / Source control above a Markdown or HTML file, plus "Full screen" for a
/// previewed HTML page.
struct FilePreviewToggleRow: View {
    @Binding var previewAsSource: Bool
    /// Full screen is the only zoom the inline frame cannot give: the live page keeps the vector
    /// sharp and offers Share as .html (G5 C8).
    let showsFullScreen: Bool
    let onFullScreen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                segment(false, label: "Preview")
                segment(true, label: "Source")
            }
            .padding(.horizontal, 4)
            .background(Palette.chip, in: .capsule)
            Spacer(minLength: 0)
            if showsFullScreen {
                Button("Full screen", action: onFullScreen)
                    .font(.paseo(.footnote, weight: .medium))
                    .foregroundStyle(Palette.secondaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Open HTML file full screen")
                    .accessibilityInputLabels(["Full screen", "Open full screen"])
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 6)
        // E3b: the panel has one canvas now; the strip sits on it, not on the page colour.
        .background(Palette.panel)
    }

    private func segment(_ source: Bool, label: LocalizedStringKey) -> some View {
        let selected = previewAsSource == source
        return Button {
            if reduceMotion {
                previewAsSource = source
            } else {
                withAnimation(Motion.disclosure.animation) { previewAsSource = source }
            }
        } label: {
            // A 36 pt pill in a 44 pt track: the whole track height takes the tap.
            Text(label)
                .font(.paseo(.footnote, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Palette.ink : Palette.secondaryInk)
                .background(selected ? Palette.background : Color.clear, in: .capsule)
                .padding(.vertical, 4)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
