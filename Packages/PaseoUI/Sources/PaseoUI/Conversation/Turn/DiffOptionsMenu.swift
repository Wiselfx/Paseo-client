#if canImport(UIKit)
import Foundation
import PaseoStore
import SwiftUI

/// The options menu in the diff sheet's top bar. Upstream: packages/app/src/git/diff-pane.tsx:883-897
/// (the two items); the words are en.ts `workspace.git.diff` (`options`, `hideWhitespace`,
/// `wrapLongLines`), packages/app/src/i18n/resources/en.ts:981-986. Each toggle keeps one label
/// that names the setting it turns on; the checkmark carries the state.
struct DiffOptionsMenu: View {
    @Binding var hideWhitespace: Bool
    @Binding var wrapLongLines: Bool

    var body: some View {
        Menu("Diff options", systemImage: "slider.horizontal.3") {
            Toggle("Hide whitespace", isOn: $hideWhitespace)
                .tint(Palette.toggleTint)
            Toggle("Wrap long lines", isOn: $wrapLongLines)
                .tint(Palette.toggleTint)
        }
        .labelStyle(.iconOnly)
    }
}
#endif
