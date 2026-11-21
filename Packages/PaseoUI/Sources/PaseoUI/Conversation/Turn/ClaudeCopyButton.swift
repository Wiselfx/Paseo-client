#if canImport(UIKit)
import PaseoStore
import SwiftUI
import UIKit

/// 28 × 28 copy affordance, the size DSH uses for its own row buttons.
struct ClaudeCopyButton: View {
    /// Read when the button is tapped, never per body pass: the text can be a whole log.
    let text: () -> String
    var label = "Copy"
    @State private var copied = false
    /// Counts taps, so every copy restarts the confirmation wait and fires its haptic, including a
    /// second tap while "Copied" already shows.
    @State private var copies = 0

    init(text: @autoclosure @escaping () -> String, label: String = "Copy") {
        self.text = text
        self.label = label
    }

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(copied ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : label)
        // Keyed by the tap count: a later copy cancels the earlier wait, so it never resets early,
        // and the task cancels with the view.
        .task(id: copies) {
            guard copies > 0 else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .paseoFeedback(.light, trigger: copies)
    }

    private func copy() {
        Clipboard.copy(text())
        copied = true
        copies += 1
    }
}
#endif
