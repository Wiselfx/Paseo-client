#if canImport(UIKit)
import Foundation

/// Repairs the way models embed Markdown that itself contains code: a ```` ```markdown ```` fence
/// holding ```` ```bash ```` … ```` ``` ```` blocks. Under CommonMark the first inner closing fence
/// closes the *outer* block, so the rest of the sample spilled out as prose and the outer closing
/// fence opened a new code block that swallowed the remainder of the message.
///
/// A Markdown fence whose body opens fences of its own length or longer (with an info string, so
/// it is unambiguously an inner block) is rewritten one marker longer than its deepest inner fence,
/// at its opening and closing lines. Every later stage (the block splitter, the rich-card
/// detector, swift-markdown) then reads the sample as one code block. Other fences are untouched.
enum MarkdownFenceNesting {
    private static let markdownLanguages: Set<String> = [
        "markdown", "md", "mdx", "gfm", "commonmark",
    ]

    static func normalized(_ source: String) -> String {
        // Nesting needs at least two fences.
        guard source.contains("```") || source.contains("~~~") else { return source }
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var changed = false
        var index = 0
        while index < lines.count {
            guard let open = fence(lines[index]) else {
                index += 1
                continue
            }
            let language =
                open.info.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            let nests = markdownLanguages.contains(language)
            var depth = 0
            var deepest = 0
            var closeIndex: Int?
            var cursor = index + 1
            while cursor < lines.count {
                if let inner = fence(lines[cursor]), inner.marker == open.marker,
                    inner.length >= open.length
                {
                    if inner.info.isEmpty {
                        // A bare fence closes the innermost open block: an inner one first.
                        if depth == 0 {
                            closeIndex = cursor
                            break
                        }
                        depth -= 1
                    } else if nests {
                        depth += 1
                        deepest = max(deepest, inner.length)
                    }
                }
                cursor += 1
            }
            if deepest > 0 {
                let length = deepest + 1
                lines[index] = rewritten(lines[index], marker: open.marker, length: length)
                if let closeIndex {
                    lines[closeIndex] = rewritten(
                        lines[closeIndex], marker: open.marker, length: length)
                }
                changed = true
            }
            index = (closeIndex ?? lines.count) + 1
        }
        return changed ? lines.joined(separator: "\n") : source
    }

    /// A CommonMark fence line: up to three spaces, then three or more backticks or tildes, then
    /// the info string (which may not contain a backtick on a backtick fence).
    private static func fence(_ line: String) -> (marker: Character, length: Int, info: String)? {
        let body = line.drop { $0 == " " }
        guard line.count - body.count <= 3, let marker = body.first, marker == "`" || marker == "~"
        else { return nil }
        let length = body.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        let info = body.dropFirst(length).trimmingCharacters(in: .whitespacesAndNewlines)
        if marker == "`", info.contains("`") { return nil }
        return (marker, length, info)
    }

    private static func rewritten(_ line: String, marker: Character, length: Int) -> String {
        let indent = line.prefix { $0 == " " }
        let rest = line.dropFirst(indent.count).drop { $0 == marker }
        return String(indent) + String(repeating: marker, count: length) + String(rest)
    }
}
#endif
