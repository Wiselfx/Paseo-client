#if canImport(UIKit)
import SwiftUI
import UIKit

/// What the composer's one trailing control is doing right now (D2 §1). The circle never changes
/// size; only its glyph and its fill do, so it reads as one button changing its mind.
enum ComposerPrimaryState: Equatable {
    /// Nothing typed, idle, the host has realtime voice: the waveform starts it.
    case voice
    /// Nothing typed, idle, no voice on this host: a send that cannot go anywhere.
    case unavailable
    /// Text or a finished attachment: send (a long press queues).
    case send
    /// Nothing typed, the agent is working: stop the turn.
    case stop
    /// Voice mode is live on this agent: the live level, and a tap mutes.
    case voiceActive
}

/// The touch-down answer every composer button gives: scale to 0.92 on the way down, back on the
/// way up, through `Motion.feedback` (D2 §1).
struct ComposerPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(
                Motion.feedback.resolved(reduceMotion: reduceMotion),
                value: configuration.isPressed)
    }
}

/// Claude's composer button: a 36 pt circle in a 44 pt hit area whose content follows the
/// composer's state — voice, send, stop — with a symbol replace and a fill crossfade.
struct ComposerPrimaryButton: View {
    let state: ComposerPrimaryState
    let isEnabled: Bool
    let isMuted: Bool
    /// Voice mode's levels, drawn as five tiny bars while voice mode is live.
    let waveform: LiveWaveformBuffer?
    let reduceMotion: Bool
    let onTap: () -> Void
    let onQueue: (() -> Void)?

    /// Set when a long press already queued; the button's own tap must then not also send, and
    /// a long press whose finger leaves the circle leaves nothing behind.
    @State private var didLongPress = false

    var body: some View {
        Button(action: tap) {
            circle
        }
        .buttonStyle(ComposerPressStyle(reduceMotion: reduceMotion))
        .disabled(!isEnabled)
        .simultaneousGesture(queuesOnLongPress)
        .accessibilityLabel(label)
        .modifier(QueueAction(action: onQueue))
        .accessibilityIdentifier(identifier)
        // ⌘↩ sends, whatever tap would have done.
        .keyboardShortcut(.return, modifiers: .command)
    }

    /// The long-press alternative as a VoiceOver action, and only where queueing exists (a draft
    /// has nowhere to queue to).
    private struct QueueAction: ViewModifier {
        let action: (() -> Void)?

        func body(content: Content) -> some View {
            if let action {
                content.accessibilityAction(named: Text("Queue message")) { action() }
            } else {
                content
            }
        }
    }

    private var circle: some View {
        ZStack {
            Circle().fill(fill)
            content
        }
        .frame(width: 36, height: 36)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .animation(Motion.swap.resolved(reduceMotion: reduceMotion), value: state)
    }

    @ViewBuilder private var content: some View {
        if state == .voiceActive, let waveform {
            LiveWaveform(
                buffer: waveform, isActive: !isMuted, barCount: 5, barWidth: 2.5, barGap: 1.5,
                maxBarHeight: 14, tint: Palette.background)
        } else {
            Image(systemName: symbol)
                .font(.glyph(.regular, weight: .semibold))
                .foregroundStyle(glyph)
                .contentTransition(.symbolEffect(.replace.downUp))
        }
    }

    /// A long press fires as soon as it is recognized (0.45 s), before the finger lifts, so the
    /// tap that follows on release is swallowed here instead of sending twice.
    private var queuesOnLongPress: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onChanged { _ in
                guard !didLongPress, let onQueue else { return }
                didLongPress = true
                onQueue()
            }
    }

    private func tap() {
        if didLongPress {
            didLongPress = false
            return
        }
        onTap()
    }

    private var symbol: String {
        switch state {
        case .voice, .voiceActive: "waveform"
        case .unavailable, .send: "arrow.up"
        case .stop: "stop.fill"
        }
    }

    /// Orange is reserved for live voice; the send is ink, like Claude's white-on-dark circle.
    private var fill: Color {
        switch state {
        case .voiceActive: Palette.orange
        case .unavailable: Palette.chip
        case .voice, .send, .stop: Palette.ink
        }
    }

    private var glyph: Color {
        switch state {
        case .unavailable: Palette.tertiaryInk
        case .voice, .send, .stop, .voiceActive: Palette.background
        }
    }

    private var label: String {
        switch state {
        case .voice: "Enable Voice mode"
        case .unavailable, .send: "Send message"
        case .stop: "Stop response"
        case .voiceActive: isMuted ? "Unmute voice mode" : "Mute Voice mode"
        }
    }

    private var identifier: String {
        switch state {
        case .voice, .voiceActive: "composer.voiceMode"
        case .unavailable, .send: "composer.send"
        case .stop: "composer.stop"
        }
    }
}
#endif
