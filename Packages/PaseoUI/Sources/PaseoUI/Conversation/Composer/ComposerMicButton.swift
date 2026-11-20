#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The dictation mic: ink on `chip`, and a filled ink circle while it listens (no accent on a
/// control, §0.1). The draft and the live conversation draw the same control.
///
/// It no longer takes the input level (E1 §2.4): the composer's body read `DictationController
/// .level`, which changes on every audio buffer, so SwiftUI re-evaluated the whole composer at
/// 30 Hz. The level now reaches the screen only through the waveform's own `Canvas`.
struct ComposerMicButton: View {
    let isListening: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.glyph(.regular, weight: .medium))
                .frame(width: ComposerMetrics.controlSize, height: ComposerMetrics.controlSize)
                .foregroundStyle(isListening ? Palette.background : Palette.ink)
                .background(isListening ? Palette.ink : Palette.chip, in: .circle)
                .frame(width: ComposerMetrics.hitSize, height: ComposerMetrics.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate")
        .accessibilityIdentifier("composer.dictate")
    }
}
#endif
