#if canImport(UIKit)
import SwiftUI

/// The brief wash behind a work section or step that a find or jump just landed on.
struct WorkFindWash: View {
    let highlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.md)
            .fill(Palette.warning.opacity(highlighted ? 0.18 : 0))
            .padding(.horizontal, -4)
            .animation(Motion.settle.resolved(reduceMotion: reduceMotion), value: highlighted)
    }
}
#endif
