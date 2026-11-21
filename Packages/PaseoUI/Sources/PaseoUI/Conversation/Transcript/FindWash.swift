#if canImport(UIKit)
import SwiftUI

/// The brief wash behind a row, section or step that a find or jump just landed on. Work rows
/// let it `bleed` a little past their content so it frames the rail beside them.
struct FindWash: View {
    let highlighted: Bool
    /// How far the wash extends past the content on each side.
    var bleed: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .fill(Palette.warning.opacity(highlighted ? 0.18 : 0))
            .padding(.horizontal, -bleed)
            .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlighted)
    }
}
#endif
