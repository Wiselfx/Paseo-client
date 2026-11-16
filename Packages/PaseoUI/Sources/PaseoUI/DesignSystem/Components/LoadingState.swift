#if canImport(UIKit)
import SwiftUI

/// A centered spinner that waits 0.3 s before showing, so fast loads never flash.
struct LoadingState: View {
    private let label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    init(_ label: String? = nil) {
        self.label = label
    }

    var body: some View {
        VStack(spacing: Space.md) {
            ProgressView()
                .controlSize(.regular)
                .tint(Palette.secondaryInk)
            if let label {
                Text(label)
                    .font(.paseo(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .animation(Motion.fade.resolved(reduceMotion: reduceMotion), value: visible)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            visible = true
        }
    }
}

/// The small spinner a row or button embeds.
struct InlineProgress: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(Palette.secondaryInk)
    }
}

#Preview("Light") {
    VStack(spacing: Space.xl) {
        LoadingState()
        LoadingState("Loading…")
            .frame(height: 120)
        HStack(spacing: Space.md) {
            InlineProgress()
            Text("Inline").font(.paseo(.footnote)).foregroundStyle(Palette.secondaryInk)
        }
    }
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: Space.xl) {
        LoadingState("Loading…")
            .frame(height: 120)
        InlineProgress()
    }
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
