import Foundation
import Highlighter

public enum ClaudeCodeSyntaxTheme: String, Sendable { case dark = "atom-one-dark", light = "atom-one-light" }

/// Offline syntax coloring. Source is data passed to bundled highlight.js, never executed.
///
/// This is the **main-actor facade**: the production path is `CodeHighlighter` (an actor, R9 §1),
/// which owns its JavaScriptCore contexts off the main thread. This type stays because the Mac
/// tests (`CodeHighlighterTests`) drive a synchronous highlighter; both use `CodeHighlightCore`, so
/// they cannot drift. `@MainActor` keeps each of its contexts on its owning UI thread.
@MainActor public final class ClaudeCodeHighlighter {
    public static let shared = ClaudeCodeHighlighter()
    public static let maximumHighlightedUTF16Length = CodeHighlighter.maximumHighlightedUTF16Length
    private var engines: [ClaudeCodeSyntaxTheme: Highlighter] = [:]
    private let cache = NSCache<NSString, NSAttributedString>()
    public init() {
        cache.countLimit = 64
        cache.totalCostLimit = 2_000_000
    }
    public func highlight(
        _ source: String, language: String?, theme: ClaudeCodeSyntaxTheme
    ) -> NSAttributedString {
        let plain = NSAttributedString(string: source)
        guard !source.isEmpty, source.utf16.count <= Self.maximumHighlightedUTF16Length,
            let canonical = CodeHighlightCore.canonicalLanguage(language)
        else { return plain }
        let key = (theme.rawValue + "\u{0}" + canonical + "\u{0}" + source) as NSString
        if let value = cache.object(forKey: key) { return value }
        let engine: Highlighter
        if let existing = engines[theme] {
            engine = existing
        } else {
            guard let created = Highlighter(), created.setTheme(theme.rawValue) else { return plain }
            engines[theme] = created
            engine = created
        }
        guard engine.supportedLanguages().contains(canonical),
            let colored = CodeHighlightCore.colorized(
                source: source, canonical: canonical, engine: engine)
        else { return plain }
        cache.setObject(colored, forKey: key, cost: source.utf16.count * 2)
        return colored
    }
}
