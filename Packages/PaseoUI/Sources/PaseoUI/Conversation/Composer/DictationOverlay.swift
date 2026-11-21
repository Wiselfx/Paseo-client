#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Upstream's dictation overlay (`dictation-controls.tsx`, `DictationOverlay`), monochrome: while
/// the mic is live the composer row becomes cancel · input meter · elapsed timer · insert ·
/// insert-and-send. It replaces the field rather than sitting beside it, the way upstream swaps
/// the whole input surface. Wording is en.ts `message.dictation` (:362-371).
struct DictationOverlay: View {
    /// The live dictation. Passed whole, not as its `duration`: that ticks once a second, and
    /// only this overlay reads it, so only this overlay re-runs on the tick, not the composer.
    let dictation: DictationController
    let onCancel: () -> Void
    let onAccept: () -> Void
    let onAcceptAndSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ComposerMetrics.controlSpacing) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.chip, in: .circle)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Cancel dictation")
            .accessibilityIdentifier("composer.dictation.cancel")

            // E1 §2.3: the meter takes every point the row does not need. A `Spacer` here used to
            // split that space with it (the meter got ~half the row); the bar count comes from
            // the width once at layout, never per frame.
            meter

            Text(formattedDuration)
                .font(.paseo(.callout, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("composer.dictation.timer")

            actionButton(
                "pencil", label: "Insert transcription",
                identifier: "composer.dictation.insert", action: onAccept)
            actionButton(
                "arrow.up", label: "Insert transcription and send",
                identifier: "composer.dictation.insertAndSend", action: onAcceptAndSend)
        }
        .frame(height: ComposerMetrics.hitSize)
        .padding(.horizontal, -ComposerMetrics.controlOverhang)
    }

    /// The live level, the same waveform the voice bar draws (D2 §4), filling the row (E1 §2.3).
    private var meter: some View {
        LiveWaveform(
            buffer: dictation.waveform, isActive: true,
            barWidth: ComposerMetrics.waveformBarWidth, barGap: ComposerMetrics.waveformBarGap,
            maxBarHeight: ComposerMetrics.waveformHeight)
    }

    private func actionButton(
        _ symbol: String, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .semibold))
                .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                .foregroundStyle(Palette.background)
                .background(Palette.ink, in: .circle)
                .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Upstream `formatDuration`: zero-padded minutes and seconds.
    private var formattedDuration: String {
        let total = max(0, Int(dictation.duration))
        return Duration.seconds(total).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}
#endif
