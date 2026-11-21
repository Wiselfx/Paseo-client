#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The composer's card: a one-line pill at rest, a lifted card once open (UX-SPEC §4.1). Shared
/// by the live conversation and the draft so both grow the same way. The live conversation always
/// passes `expanded: true` (V5 §4.4); only the draft still collapses to the pill.
struct ComposerCardChrome: ViewModifier {
    let expanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var radius: CGFloat { expanded ? Radius.composer : Radius.composerPill }

    /// The soft lift Claude's card has in light (E1 §4); nothing in dark.
    private var shadow: Color { colorScheme == .dark ? .clear : Palette.composerShadow }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ComposerMetrics.sideInset)
            .padding(.vertical, expanded ? ComposerMetrics.verticalInset : 0)
            .frame(minHeight: ComposerMetrics.pillHeight)
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Palette.composer)
                    .stroke(Palette.composerBorder, lineWidth: ComposerMetrics.hairline)
                    .shadow(color: shadow, radius: ComposerMetrics.shadowRadius,
                            y: ComposerMetrics.shadowY)
            }
    }
}
#endif
