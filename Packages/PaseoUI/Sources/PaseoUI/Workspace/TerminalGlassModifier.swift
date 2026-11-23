#if canImport(UIKit)
import SwiftUI

/// Liquid Glass for the terminal's floating controls, with a solid material and a hairline instead
/// when Reduce Transparency is on, so a control never depends on seeing through to the terminal.
///
/// A control that morphs between places (the chip bar's selection) passes a morph identity: the
/// `glassEffectID` goes directly on the view that carries the `glassEffect`, so the enclosing
/// `GlassEffectContainer` matches the two shapes. Under Reduce Transparency there is no glass to
/// morph and the identity is simply not applied.
struct TerminalGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    /// The glass's identity for morphing, and the namespace it lives in; nil for a fixed control.
    /// Constant for a given call site, so the branch below never flips at run time.
    let morph: (id: String, namespace: Namespace.ID)?

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
                .overlay { shape.stroke(Palette.cardBorder, lineWidth: TerminalChrome.hairline) }
        } else if let morph {
            content
                .glassEffect(glass, in: shape)
                .glassEffectID(morph.id, in: morph.namespace)
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
        modifier(
            TerminalGlassModifier(shape: shape, interactive: interactive, tint: tint, morph: nil))
    }

    /// Glass that morphs: the same `id` appearing on another view in the same
    /// `GlassEffectContainer` slides and reshapes the glass there instead of fading.
    func terminalGlass<S: Shape>(
        _ shape: S, morphID id: String, in namespace: Namespace.ID
    ) -> some View {
        modifier(
            TerminalGlassModifier(
                shape: shape, interactive: false, tint: nil, morph: (id: id, namespace: namespace)))
    }
}
#endif
