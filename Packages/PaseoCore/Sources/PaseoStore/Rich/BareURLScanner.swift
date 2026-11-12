import Foundation

// MARK: - BareURLScanner (J2 §3)

// NOTE: J2: swift-markdown has no GFM autolink extension, so `- https://swift.org/blog/`
// kept its URL as plain `.text` and the reader got black, untappable prose. The detector
// deliberately never turns a standalone URL line into a card inside a list (upstream
// parity), so the link is what the reader should get there. This finds the URLs so the
// inline conversion can wrap them; it runs once per parsed document (the document cache),
// never per render, and it never rewrites the markdown source — an authored autolink would
// turn a standalone URL into an authored link and kill its link card / YouTube player.

/// `http://` and `https://` URLs inside plain text, with their ranges.
public enum BareURLScanner {
    /// Where each URL ends: whitespace and `<>"` always stop it; a trailing `.,;:!?` is
    /// punctuation, and a closing `)` or `]` belongs to the URL only when the URL opened
    /// the same character before it (`https://w.org/wiki/Foo_(bar)` keeps both parens,
    /// `(see https://w.org/x)` drops the sentence's).
    public static func ranges(in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard let schemeStart = nextScheme(text, from: i) else { break }
            var end = schemeStart
            var openParens = 0
            var openBrackets = 0
            while end < text.endIndex {
                let char = text[end]
                if char == "(" {
                    openParens += 1
                } else if char == "[" {
                    openBrackets += 1
                } else if char == ")" {
                    guard openParens > 0 else { break }
                    openParens -= 1
                } else if char == "]" {
                    guard openBrackets > 0 else { break }
                    openBrackets -= 1
                } else if char.isWhitespace || char == "<" || char == ">" || char == "\"" {
                    break
                }
                end = text.index(after: end)
            }
            let trimmed = trimTrailingPunctuation(schemeStart..<end, in: text)
            // A host is required: `https://` alone is a half-typed scheme, not a link.
            let schemeLength = text[schemeStart...].hasPrefix("https://") ? 8 : 7
            if text.distance(from: schemeStart, to: trimmed) > schemeLength {
                found.append(schemeStart..<trimmed)
            }
            i = end
        }
        return found
    }

    /// The start of the next `http://` / `https://` at or after `start`, any case.
    private static func nextScheme(_ text: String, from start: String.Index) -> String.Index? {
        var i = start
        while i < text.endIndex {
            let head = text[i...].prefix(8).lowercased()
            if head.hasPrefix("http://") || head.hasPrefix("https://") { return i }
            i = text.index(after: i)
        }
        return nil
    }

    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    private static func trimTrailingPunctuation(
        _ range: Range<String.Index>, in text: String
    ) -> String.Index {
        var end = range.upperBound
        while end > range.lowerBound, trailingPunctuation.contains(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        return end
    }
}
