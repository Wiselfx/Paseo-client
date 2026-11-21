#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Model *Thinking*" in one grey chip (§4.1b). A draft passes its provider's label, because the
/// provider is still a choice there (§3.1); a live agent has one already and shows the model only.
/// No accent in any state (§0.1).
struct ComposerModelChip: View {
    var modelLabel: String
    var thinkingLabel: String?
    /// Draft only: draws the provider's glyph in front of the model.
    var providerLabel: String?
    /// Draft only: the provider's `iconSvg`, so the glyph is the real mark.
    var providerIconSvg: String?
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            chipLabels
                .padding(.horizontal, ComposerMetrics.chipPadding)
                // 36 pt at the default type size; taller type grows it rather than clipping.
                .frame(minHeight: ComposerMetrics.controlSize)
                .background(Palette.chip, in: .capsule)
                // Hit area: the capsule stays 36 pt tall, the touch target is 44.
                .frame(minHeight: ComposerMetrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        // The chip wins its space before the fixed-size controls take theirs, so it shrinks
        // rather than pushing the mic and the primary off the row.
        .layoutPriority(1)
        // The label names the control; the value is what is selected, so VoiceOver reads the
        // current model, and Voice Control can say the model's visible name.
        .accessibilityLabel("Model")
        .accessibilityValue([providerLabel, modelLabel, thinkingLabel].compactMap { $0 }.formatted())
        .accessibilityInputLabels([Text("Model"), Text(modelLabel)])
        .accessibilityIdentifier("composer.model")
    }

    /// D2 §1: the chip must never read "Bea… Me…". The thinking label is dropped first, then the
    /// model name truncates in the middle — losing the middle of a name is readable, losing both
    /// ends is not.
    private var chipLabels: some View {
        ViewThatFits(in: .horizontal) {
            labelRow(model: modelLabel, thinking: thinkingLabel, truncation: .tail)
            labelRow(model: modelLabel, thinking: nil, truncation: .tail)
            labelRow(model: modelLabel, thinking: nil, truncation: .middle)
        }
    }

    private func labelRow(
        model: String, thinking: String?, truncation: Text.TruncationMode
    ) -> some View {
        HStack(spacing: 4) {
            if let providerLabel {
                ProviderGlyph(label: providerLabel, iconSvg: providerIconSvg)
            }
            Text(model)
                .lineLimit(1)
                .truncationMode(truncation)
            if let thinking {
                Text(thinking)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(truncation)
            }
        }
        .font(.paseo(.callout))
        .foregroundStyle(Palette.ink)
    }
}
#endif
