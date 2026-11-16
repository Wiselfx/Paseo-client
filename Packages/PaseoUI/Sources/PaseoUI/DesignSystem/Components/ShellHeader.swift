#if canImport(UIKit)
import SwiftUI

/// A screen's 48 pt bar: a leading glass button (sidebar or back), a centered title that fills
/// the width, and a trailing slot of 44 pt buttons.
struct ShellHeader<Title: View, Trailing: View>: View {
    enum Leading {
        case sidebar(() -> Void)
        case back(() -> Void)
        case none
    }

    private let leading: Leading
    private let title: () -> Title
    private let trailing: () -> Trailing
    /// False (the default, every other screen): the row centres its items. True: the row aligns
    /// its items to the top, so the buttons stay on the top row while a title grows taller (N6 C).
    private let alignsControlsToTop: Bool

    init(
        leading: Leading,
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder trailing: @escaping () -> Trailing,
        alignsControlsToTop: Bool = false
    ) {
        self.leading = leading
        self.title = title
        self.trailing = trailing
        self.alignsControlsToTop = alignsControlsToTop
    }

    var body: some View {
        HStack(
            alignment: alignsControlsToTop ? VerticalAlignment.top : VerticalAlignment.center,
            spacing: Space.sm
        ) {
            leadingButton
            title()
                .frame(maxWidth: .infinity)
            HStack(spacing: Space.sm) {
                trailing()
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        }
        .frame(minHeight: 48)
        .padding(.horizontal, Space.md)
    }

    @ViewBuilder private var leadingButton: some View {
        switch leading {
        case .sidebar(let action):
            GlassIconButton(label: "Open sidebar", action: action) {
                UnequalMenu().stroke(
                    Palette.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                )
                .frame(width: 18, height: 17)
            }
        case .back(let action):
            GlassIconButton(systemName: "chevron.left", label: "Back", action: action)
        case .none:
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
    }
}

#Preview("Light") {
    VStack(spacing: Space.lg) {
        ShellHeader(leading: .sidebar({})) {
            Text("Title").font(.paseo(.title)).foregroundStyle(Palette.ink)
        } trailing: {
            Image(systemName: "sidebar.right").font(.glyph(.regular, weight: .medium))
        }
        ShellHeader(leading: .back({})) {
            Text("Title").font(.paseo(.title)).foregroundStyle(Palette.ink)
        } trailing: {}
        ShellHeader(leading: .none) {
            Text("Title").font(.paseo(.title)).foregroundStyle(Palette.ink)
        } trailing: {}
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: Space.lg) {
        ShellHeader(leading: .sidebar({})) {
            Text("Title").font(.paseo(.title)).foregroundStyle(Palette.ink)
        } trailing: {
            Image(systemName: "sidebar.right").font(.glyph(.regular, weight: .medium))
        }
    }
    .padding()
    .background(Palette.background)
    .preferredColorScheme(.dark)
}
#endif
