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
    /// The cost each entry was stored with, so eviction subtracts exactly what was added.
    private var costs: [HighlightKey: Int] = [:]
    private let countLimit = 64
    private let costLimit = 2_000_000

    private typealias HighlightKey = CodeHighlightKey

    /// Nil means "no highlighting": empty, oversized, unknown language, a theme the engine could
    /// not load, or output that would not round-trip. The caller keeps its plain text.
    func highlight(
        _ code: String, language: String?, theme: ClaudeCodeSyntaxTheme
    ) async -> AttributedString? {
        guard !code.isEmpty, code.utf16.count <= Self.maximumHighlightedUTF16Length else {
            return nil
        }
        guard let canonical = CodeHighlightCore.canonicalLanguage(language),
            let key = HighlightKey(code: code, language: language, theme: theme)
        else { return nil }
        if let hit = cache[key] {
            touch(key)
            CodeHighlightMirror.store(hit, for: key)
            return hit
        }
        PaseoPerf.count("hl.miss")
        let span = PaseoPerf.begin("code.highlight")
        defer { PaseoPerf.end(span) }
        guard let engine = engine(for: theme),
            engine.supportedLanguages().contains(canonical),
            let colored = CodeHighlightCore.colorized(
                source: code, canonical: canonical, engine: engine),
            let attributed = try? AttributedString(colored, including: \.uiKit)
        else { return nil }
        store(attributed, for: key, cost: code.utf16.count * 2)
        CodeHighlightMirror.store(attributed, for: key)
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
        if cache.removeValue(forKey: key) != nil, let index = order.firstIndex(of: key) {
            order.remove(at: index)
            cost -= costs.removeValue(forKey: key) ?? 0
        }
        cache[key] = value
        costs[key] = newCost
        order.append(key)
        cost += newCost
        while order.count > countLimit || (cost > costLimit && order.count > 1) {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
            cost -= costs.removeValue(forKey: oldest) ?? 0
        }
    }
}

/// Identity of one highlight: theme, canonical language, the source's hash and length. Never the source
/// itself, so a cache does not retain every streamed revision of a block.
struct CodeHighlightKey: Hashable, Sendable {
    let theme: ClaudeCodeSyntaxTheme
    let language: String
    let hash: Int
    let count: Int

    init?(code: String, language: String?, theme: ClaudeCodeSyntaxTheme) {
        guard !code.isEmpty, code.utf16.count <= CodeHighlighter.maximumHighlightedUTF16Length,
            let canonical = CodeHighlightCore.canonicalLanguage(language)
        else { return nil }
        self.theme = theme
        self.language = canonical
        self.hash = code.hashValue
        self.count = code.utf16.count
    }
}

/// A thread-safe copy of the actor's finished highlights (W1), readable without awaiting: a code block
/// whose highlight already exists (the warm-up, an earlier visit) draws it on its first pass, so the block
/// is laid out once instead of plain first and again when the actor answers.
enum CodeHighlightMirror {
    private static let table = ProseCache<CodeHighlightKey, AttributedString>(
        budget: 8 * 1024 * 1024, countLimit: 128, cost: { key, _ in key.count * 4 })

    static func store(_ value: AttributedString, for key: CodeHighlightKey) {
        table.setValue(value, for: key)
    }

    static func value(code: String, language: String?, theme: ClaudeCodeSyntaxTheme) -> AttributedString? {
        guard let key = CodeHighlightKey(code: code, language: language, theme: theme) else { return nil }
        return table.value(for: key)
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
