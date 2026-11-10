import Foundation
import Highlighter
#if canImport(UIKit)
import UIKit
#endif

/// The shared, **off-main** syntax highlighter (R9 §1).
///
/// One JavaScriptCore context per theme lives on this actor, never on the main actor: a 100 KB
/// block of JS-side tokenizing is the expensive part of a code block's first paint. Results are
/// cached keyed by `(theme, language, hash(source), utf16.count)` — never by the source itself, so
/// the cache does not retain every streamed revision of a block.
actor CodeHighlighter {
    static let shared = CodeHighlighter()
    static let maximumHighlightedUTF16Length = 100_000

    private var engines: [ClaudeCodeSyntaxTheme: Highlighter] = [:]
    /// Insertion order, oldest first, for the LRU eviction.
    private var order: [HighlightKey] = []
    private var cache: [HighlightKey: AttributedString] = [:]
    private var cost = 0
    private let countLimit = 64
    private let costLimit = 2_000_000

    private struct HighlightKey: Hashable {
        let theme: ClaudeCodeSyntaxTheme
        let language: String
        let hash: Int
        let count: Int
    }

    /// Nil means "no highlighting": empty, oversized, unknown language, a theme the engine could
    /// not load, or output that would not round-trip. The caller keeps its plain text.
    func highlight(
        _ code: String, language: String?, theme: ClaudeCodeSyntaxTheme
    ) async -> AttributedString? {
        guard !code.isEmpty, code.utf16.count <= Self.maximumHighlightedUTF16Length else {
            return nil
        }
        guard let canonical = CodeHighlightCore.canonicalLanguage(language) else { return nil }
        let key = HighlightKey(
            theme: theme, language: canonical, hash: code.hashValue, count: code.utf16.count)
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        guard let engine = engine(for: theme),
            engine.supportedLanguages().contains(canonical),
            let colored = CodeHighlightCore.colorized(
                source: code, canonical: canonical, engine: engine),
            let attributed = try? AttributedString(colored, including: \.uiKit)
        else { return nil }
        store(attributed, for: key, cost: code.utf16.count * 2)
        return attributed
    }

    private func engine(for theme: ClaudeCodeSyntaxTheme) -> Highlighter? {
        if let existing = engines[theme] { return existing }
        guard let created = Highlighter(), created.setTheme(theme.rawValue) else { return nil }
        engines[theme] = created
        return created
    }

    private func touch(_ key: HighlightKey) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    private func store(_ value: AttributedString, for key: HighlightKey, cost newCost: Int) {
        if let existing = cache.removeValue(forKey: key),
            let index = order.firstIndex(of: key)
        {
            order.remove(at: index)
            cost -= existing.characters.count * 2
        }
        cache[key] = value
        order.append(key)
        cost += newCost
        while order.count > countLimit || (cost > costLimit && order.count > 1) {
            let oldest = order.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                cost -= removed.characters.count * 2
            }
        }
    }
}

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
