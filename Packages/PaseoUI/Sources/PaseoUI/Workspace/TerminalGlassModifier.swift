#if canImport(UIKit)
import SwiftUI

/// Liquid Glass for the terminal's floating controls, with a solid material and a hairline instead
/// when Reduce Transparency is on, so a control never depends on seeing through to the terminal.
struct TerminalGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Palette.cardBorder, lineWidth: 0.5) }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }
}

extension View {
    /// A floating terminal control's surface: glass, or a solid material under Reduce Transparency.
    func terminalGlass<S: Shape>(
        _ shape: S, interactive: Bool = false, tint: Color? = nil
    ) -> some View {
        modifier(TerminalGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }
}
#endif
