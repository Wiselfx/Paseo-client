#if canImport(UIKit)
import SwiftUI

/// M7g: file paths in chat text rendered as tappable links that open the workspace file viewer
/// (`paseo-file://file?path=…`).
///
/// Tokens are *candidates*, never resolved against the workspace at render time — the viewer's
/// own not-found state is the resolution. Matching: absolute/home-relative paths and relative
/// paths with at least one slash, ending in a `name.ext` filename (2–8 chars). The final
/// extension requirement is deliberate: bare words and bare directories never match. `.code`
/// spans are excluded by the callers.
enum FilePathLinks {
    static let scheme = "paseo-file"
    static let host = "file"
    static let queryName = "path"

    /// Path candidate, optionally `@`-prefixed, any relative/absolute shape.
    private static let pathPattern =
        #"(?<![\w/~@.-])(?:@)?(?:~?/|\.{1,2}/)?(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,8}(?![\w/~.-])"#

    /// The raw text of the matched token (including a leading `@`).
    struct Match {
        let range: NSRange
        let path: String
    }

    static func matches(in text: String) -> [Match] {
        guard let pathRegex else { return [] }
        let ns = text as NSString
        return pathRegex
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { result in
                let raw = ns.substring(with: result.range)
                let path = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
                return Match(range: result.range, path: path)
            }
    }

    static func url(forPath path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: queryName, value: path)]
        return components.url
    }

    static func path(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == queryName })?.value
    }

    // MARK: Markdown pre-pass (assistant prose)

    private static let pathRegex: NSRegularExpression? = try? NSRegularExpression(pattern: pathPattern)

    /// Replaces every path candidate outside protected spans (code fences, inline code, authored
    /// links) with a `paseo-file:` markdown link whose display text is the path itself — the same
    /// shape as upstream's `linkifyLocalPaths`. Path matches are conservative (a final path part
    /// with a dotted extension); `@` is stripped for the target.
    static func linkified(markdown: String) -> String {
        guard let pathRegex else { return markdown }
        let ns = markdown as NSString
        let full = NSRange(location: 0, length: ns.length)
        let protected = protectedRanges(of: markdown)

        var output = ""
        var cursor = 0
        for match in pathRegex.matches(in: markdown, range: full) {
            if match.range.location < cursor { continue }
            if protected.contains(where: { NSIntersectionRange($0, match.range).length != 0 }) {
                continue
            }
            let token = ns.substring(with: match.range)
            let path = token.hasPrefix("@") ? String(token.dropFirst()) : token
            // A candidate ending in an authored-link destination would have matched inside it;
            // anything else here is safe to wrap.
            guard let url = url(forPath: path) else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += "[\(token)](\(url.absoluteString))"
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { output += ns.substring(from: cursor) }
        return output
    }

    /// `linkified` memoized by source, for prose rendering (P3).
    ///
    /// Linkifying is pure: four regex passes over the whole answer, ~0.7 ms per 8 k-char message,
    /// and SwiftUI asks for it on every body evaluation — not only when the text changed. The
    /// table is small and evicts wholesale, like `RichContentCache`, so streamed text (a new
    /// string per token) only ever costs the parse it must cost anyway.
    @MainActor static func linkifiedForProse(_ markdown: String) -> String {
        if let cached = linkifiedCache[markdown] { return cached }
        let result = linkified(markdown: markdown)
        if linkifiedCache.count >= 64 { linkifiedCache.removeAll(keepingCapacity: true) }
        linkifiedCache[markdown] = result
        return result
    }

    /// Main-actor only, reached through `linkifiedForProse`.
    @MainActor private static var linkifiedCache: [String: String] = [:]

    /// Fenced code blocks, inline code spans and authored links — path candidates never linkify
    /// inside them.
    private static func protectedRanges(of text: String) -> [NSRange] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [NSRange] = []

        // Fenced code blocks (``` or ~~~), line-anchored.
        let fencePattern = #"(?:^|\n)```[\s\S]*?(?:```|$)|(?:^|\n)~~~[\s\S]*?(?:~~~|$)"#
        if let fenceRegex = try? NSRegularExpression(pattern: fencePattern) {
            ranges += fenceRegex.matches(in: text, range: full).map(\.range)
        }
        // Inline code spans (any backtick run, same length closed).
        let inlinePattern = #"`+[^`\n]*?`+"#
        if let inlineRegex = try? NSRegularExpression(pattern: inlinePattern) {
            ranges += inlineRegex.matches(in: text, range: full).map(\.range)
        }
        // Authored links.
        if let authoredRegex = try? NSRegularExpression(pattern: #"\[[^\]]*\]\([^)]*\)"#) {
            ranges += authoredRegex.matches(in: text, range: full).map(\.range)
        }
        return ranges
    }

    /// `text` with every file-path candidate turned into a `paseo-file:` link.
    static func attributed(
        _ text: String, font: Font, foreground: Color, linkColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        let ns = text as NSString
        var cursor = 0
        for match in matches(in: text) {
            if match.range.location > cursor {
                var plain = AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
                plain.font = font
                plain.foregroundColor = foreground
                result.append(plain)
            }
            var linked = AttributedString(ns.substring(with: match.range))
            linked.font = ClaudeTypography().mono(13)
            linked.foregroundColor = linkColor
            linked.underlineStyle = .single
            linked.link = url(forPath: match.path)
            result.append(linked)
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            var plain = AttributedString(ns.substring(from: cursor))
            plain.font = font
            plain.foregroundColor = foreground
            result.append(plain)
        }
        return result
    }
}
#endif
