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

    init(text: @autoclosure @escaping () -> String, label: String = "Copy") {
        self.text = text
        self.label = label
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = text()
            Haptics.light()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.glyph(.regular, weight: .light))
                .foregroundStyle(copied ? Palette.ink : Palette.tertiaryInk)
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : label)
    }
}
#endif
