#if canImport(UIKit)
import SwiftUI

/// Lays the terminals out at the stage's *settled* size: while the size is changing (the keyboard
/// or key bar animating, a rotation, a Split View resize) they keep the last settled size, pinned
/// to the bottom and clipped, and take the new one once it has held for `settleDelay`.
///
/// Each step of a resize used to resize the emulator's grid at once (rows moving into scrollback)
/// while the PTY heard about it only after the debounce, so a TUI such as Claude Code kept drawing
/// for the old size and erased the wrong lines: fragments of earlier frames stayed on screen. Now
/// the grid changes once, and the coordinator sends that size to the PTY in the same turn.
///
/// Bottom-pinned, so the prompt stays just above the keyboard while it opens; while it closes the
/// stage shows its canvas above the terminal for the settle delay.
struct TerminalSettledFrame<Content: View>: View {
    @ViewBuilder let content: Content

    /// The keyboard's own animation is about this long: the grid changes once it is done.
    static var settleDelay: Duration { .milliseconds(300) }

    @State private var measured: CGSize = .zero
    @State private var settled: CGSize?

    var body: some View {
        let size = settled ?? measured
        content
            .frame(
                width: size.width > 0 ? size.width : nil,
                height: size.height > 0 ? size.height : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                measured = newSize
                // The first size lays the terminals out at once: there is nothing to keep yet.
                if settled == nil { settled = newSize }
            }
            .task(id: measured) { await settle() }
    }

    private func settle() async {
        guard settled != measured else { return }
        try? await Task.sleep(for: Self.settleDelay)
        guard !Task.isCancelled else { return }
        settled = measured
    }
}
#endif
