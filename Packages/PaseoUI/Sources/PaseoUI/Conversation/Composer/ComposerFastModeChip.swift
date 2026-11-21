#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The "Fast" chip in the control row, shown while the provider's fast mode is on; a tap turns it
/// off.
struct ComposerFastModeChip: View {
    let onTurnOff: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.selection()
            onTurnOff()
        } label: {
            Label {
                Text("Fast")
                    .font(.paseo(.footnote, weight: .semibold))
            } icon: {
                Image(systemName: "bolt.fill")
                    .font(.glyph(.small, weight: .semibold))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, ComposerMetrics.chipPadding)
            .frame(minHeight: ComposerMetrics.controlSize)
            .background(Palette.chip, in: .capsule)
            .frame(minHeight: ComposerMetrics.hitSize)
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Fast mode on; turn off")
        .accessibilityIdentifier("composer.fastmode")
    }
}
#endif
