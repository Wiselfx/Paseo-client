#if canImport(UIKit)
import UIKit

/// Touches, once and at idle, what the first composer / new-session / code-block appearance would
/// otherwise build on the way to its first frame (W1): the composer's `UITextView` class and its TextKit
/// stack with the body face laid out once, the SF Symbols the composer and the draft page draw, and the
/// syntax highlighter's JavaScriptCore contexts (off the main actor). Nothing is attached to a window,
/// nothing is shown, no setting of the field is touched; the main-thread part is a few milliseconds at a
/// moment the user is not interacting (a second or two after the shell appears).
@MainActor
enum ComposerWarmup {
    private static var done = false

    static func scheduleOnce() {
        guard !done else { return }
        done = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            PaseoPerf.measure("warm.composer") { warmComposerField() }
            try? await Task.sleep(for: .milliseconds(300))
            PaseoPerf.measure("warm.symbols") { warmSymbols() }
            // Off main: the actor builds one engine per theme on first use.
            _ = await CodeHighlighter.shared.highlight(
                "let a = 1", language: "swift", theme: .dark)
            _ = await CodeHighlighter.shared.highlight(
                "let a = 1", language: "swift", theme: .light)
        }
    }

    private static func warmComposerField() {
        let field = ComposerUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        field.applyStyle(placeholder: "Message")
        field.text = "Warm"
        _ = field.sizeThatFits(CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        field.layoutIfNeeded()
    }

    private static func warmSymbols() {
        let names = [
            "plus", "arrow.up", "mic", "mic.fill", "stop.fill", "xmark", "bolt.fill", "sparkles",
            "chevron.up.chevron.down", "chevron.down", "square.on.square",
            "arrow.up.left.and.arrow.down.right", "photo.on.rectangle", "camera", "folder", "at",
            "plus.bubble", "doc.on.doc", "sidebar.right", "folder.badge.plus",
        ]
        let configuration = UIImage.SymbolConfiguration(textStyle: .body)
        for name in names { _ = UIImage(systemName: name, withConfiguration: configuration) }
    }
}
#endif
