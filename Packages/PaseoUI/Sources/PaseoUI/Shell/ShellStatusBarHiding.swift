#if canImport(UIKit)
import SwiftUI

/// Applies the status bar visibility the terminal's full screen asks for
/// (`ShellDrawer.setStatusBarHidden`) at the shell's root, where it reaches the window. The flag
/// is this modifier's own state, so a full-screen toggle re-evaluates this modifier and nothing
/// above or inside it: the shell's body (and the roots it builds) stays untouched.
struct ShellStatusBarHiding: ViewModifier {
    let drawer: ShellDrawer

    @State private var isHidden = false

    func body(content: Content) -> some View {
        content
            .statusBarHidden(isHidden)
            .onAppear(perform: connect)
    }

    private func connect() {
        drawer.onStatusBarHiddenChange = { hidden in
            if isHidden != hidden { isHidden = hidden }
        }
    }
}
#endif
