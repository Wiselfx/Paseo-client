import Foundation
import Highlighter
#if canImport(UIKit)
import UIKit
#endif

/// The pure parts of highlighting, shared by the actor and the main-actor facade the Mac tests use.
enum CodeHighlightCore {
    /// highlight.js names differ from fenced-code tags; anything else is passed through.
    static func canonicalLanguage(_ language: String?) -> String? {
        guard
            let name = language?.split(whereSeparator: { $0.isWhitespace }).first?.lowercased(),
            !name.isEmpty
        else { return nil }
        let aliases = [
            "py": "python", "js": "javascript", "ts": "typescript", "sh": "bash", "rb": "ruby",
            "rs": "rust", "c++": "cpp", "c#": "csharp", "html": "xml",
        ]
        return aliases[name] ?? name
    }

    /// Token foreground colors only: SwiftUI owns font, spacing, selection and the card background.
    /// Nil when the engine can't color this source or the output would not round-trip exactly.
    static func colorized(
        source: String, canonical: String, engine: Highlighter
    ) -> NSAttributedString? {
        guard let colored = engine.highlight(source, as: canonical), colored.string == source
        else { return nil }
        let result = NSMutableAttributedString(string: source)
        colored.enumerateAttributes(in: NSRange(location: 0, length: colored.length)) {
            attributes, range, _ in
            if let color = attributes[.foregroundColor] {
                result.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        return NSAttributedString(attributedString: result)
    }
}
