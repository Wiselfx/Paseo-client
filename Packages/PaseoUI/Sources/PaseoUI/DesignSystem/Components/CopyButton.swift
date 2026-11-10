#if canImport(UIKit)
import SwiftUI

/// A 44 pt copy affordance: the symbol becomes a checkmark for two seconds, with a selection
/// haptic.
struct CopyButton: View {
    private let text: String
    private let label: String

    @State private var copied = false

    init(text: String, label: String = "Copy") {
        self.text = text
        self.label = label
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Clipboard.copy(text)
            Haptics.selection()
            withAnimation(Motion.feedback.resolved(reduceMotion: reduceMotion)) { copied = true }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.glyph(.regular, weight: .medium))
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : label)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.feedback.resolved(reduceMotion: reduceMotion)) { copied = false }
        }
    }
}

#Preview("Light") {
    HStack {
        CopyButton(text: "hello")
        CopyButton(text: "hello", label: "Copy path")
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    CopyButton(text: "hello")
        .padding()
        .background(Palette.background)
        .preferredColorScheme(.dark)
}
#endif
