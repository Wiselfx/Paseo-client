#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The live voice row: mute toggle, live level, stop/interrupt (upstream wording).
struct VoiceBar: View {
    let voice: VoiceModeSession
    let engine: VoiceAudioEngine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ComposerMetrics.controlSpacing) {
            Button {
                Haptics.selection()
                voice.setMuted(!voice.isMuted)
            } label: {
                Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                    .foregroundStyle(.white)
                    .background(voice.isMuted ? Palette.failureInk : Palette.chip, in: .circle)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel(voice.isMuted ? "Unmute voice" : "Mute voice")
            .accessibilityIdentifier("composer.voice.mute")

            // The live level fills everything between the two circles (E1 §2.3). The bar reads
            // the level from its own ring at draw time; this view never reads `voice.volume`, so
            // an audio buffer cannot re-evaluate the composer (H1 §3).
            LiveWaveform(
                buffer: engine.waveform, isActive: !voice.isMuted,
                barWidth: ComposerMetrics.waveformBarWidth, barGap: ComposerMetrics.waveformBarGap,
                maxBarHeight: ComposerMetrics.waveformHeight,
                accessibilityText: "Voice volume")
                .accessibilityIdentifier("composer.voice.volume")

            Button {
                Haptics.selection()
                Task { await voice.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.glyph(.regular, weight: .medium))
                    .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                    .foregroundStyle(.white)
                    .background(Palette.failureInk, in: .circle)
                    .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                    .contentShape(.rect)
            }
            .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel("Stop realtime voice and interrupt turn")
            .accessibilityIdentifier("composer.voice.stop")
            .disabled(voice.phase == .stopping)
        }
        // The circles sit 8 pt from the card's edge, like every other row (E1 §4).
        .padding(.horizontal, -ComposerMetrics.controlOverhang)
    }
}
#endif
