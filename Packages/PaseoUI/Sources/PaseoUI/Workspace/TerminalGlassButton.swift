#if canImport(UIKit)
import SwiftUI

/// The one icon-only glass control the terminal chrome uses: a 44 pt circle where the glass,
/// the label and the hit shape are the same shape. Glass is only for controls that float over
/// or against the terminal.
struct TerminalGlassButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var identifier = ""
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.glyph(.small, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: TerminalChrome.hit, height: TerminalChrome.hit)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
        .terminalGlass(.circle, interactive: true)
        .animation(Motion.feedback.resolved(reduceMotion: reduceMotion), value: systemImage)
        .accessibilityIdentifier(identifier)
    }
}
#endif
