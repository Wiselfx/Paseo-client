#if canImport(UIKit)
import SwiftTerm
import UIKit

/// SwiftTerm's view with its Metal renderer switched on.
///
/// SwiftTerm draws with CoreGraphics by default; its Metal path rasterises glyphs into an atlas and
/// draws cells as GPU quads, which keeps full-screen TUI repaints (Claude Code, pi, editors) off
/// the CPU. `setUseMetal` needs the view in a window, so it is enabled on the first attach. A
/// device without Metal throws, and the view simply keeps the CoreGraphics renderer.
final class PaseoTerminalSurface: TerminalView {
    private var triedMetal = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !triedMetal else { return }
        triedMetal = true
        try? setUseMetal(true)
    }
}
#endif
