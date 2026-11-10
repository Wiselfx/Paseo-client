#if canImport(UIKit)
import SwiftUI

/// A 44 pt glass circle around one symbol or a custom shape, with its accessibility label.
struct GlassIconButton<Label: View>: View {
    private let label: String
    private let action: () -> Void
    @ViewBuilder private let content: () -> Label

    init(label: String, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Label) {
        self.label = label
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(in: .circle)
        .accessibilityLabel(label)
    }
}

extension GlassIconButton where Label == Image {
    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.init(label: label, action: action) {
            Image(systemName: systemName).font(.glyph(.regular, weight: .medium))
        }
    }
}

#Preview("Light") {
    HStack(spacing: Space.md) {
        GlassIconButton(systemName: "chevron.left", label: "Back") {}
        GlassIconButton(label: "Open sidebar", action: {}) {
            UnequalMenu().stroke(
                Palette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: 18, height: 17)
        }
        GlassIconButton(systemName: "xmark", label: "Close") {}
            .disabled(true)
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: Space.md) {
        GlassIconButton(systemName: "chevron.left", label: "Back") {}
        GlassIconButton(label: "Open sidebar", action: {}) {
            UnequalMenu().stroke(
                Palette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: 18, height: 17)
        }
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
