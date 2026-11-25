#if canImport(UIKit)
import SwiftTerm
import UIKit

/// SwiftTerm's view with its Metal renderer switched on, and its keyboard raised in English.
///
/// SwiftTerm draws with CoreGraphics by default; its Metal path rasterises glyphs into an atlas and
/// draws cells as GPU quads, which keeps full-screen TUI repaints (Claude Code, pi, editors) off
/// the CPU. `setUseMetal` needs the view in a window, so it is enabled on the first attach. A
/// device without Metal throws, and the view simply keeps the CoreGraphics renderer.
final class PaseoTerminalSurface: TerminalView {
    private var triedMetal = false
    private var observingInputModes = false
    private var layoutChosen = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !triedMetal else { return }
        triedMetal = true
        try? setUseMetal(true)
    }

    /// Raises the keyboard in English whatever layout was last in use. With a Pinyin keyboard the
    /// letters sit in its candidate bar and nothing reaches the shell. The globe key still switches:
    /// once the user has picked a layout, this returns that layout until the keyboard is next
    /// raised. SwiftTerm reads this value for its Korean composition fix.
    override var textInputMode: UITextInputMode? {
        let current = super.textInputMode
        if layoutChosen { return current }
        let english = UITextInputMode.activeInputModes.first { $0.primaryLanguage?.hasPrefix("en") == true }
        return english ?? current
    }

    override func becomeFirstResponder() -> Bool {
        if !observingInputModes {
            observingInputModes = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(layoutChanged),
                name: UITextInputMode.currentInputModeDidChangeNotification, object: nil)
        }
        // Only a real raise starts the layout afresh. SwiftTerm also calls this on a long press and
        // from its context menu while the keyboard is already up, and that must not undo the layout
        // the user just picked.
        if !isFirstResponder { layoutChosen = false }
        return super.becomeFirstResponder()
    }

    /// Input-mode changes reach every view, so this acts only while the terminal holds the keyboard.
    @objc private func layoutChanged() {
        guard isFirstResponder else { return }
        layoutChosen = super.textInputMode?.primaryLanguage?.hasPrefix("en") != true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
#endif
