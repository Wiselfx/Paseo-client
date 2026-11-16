import Foundation

// MARK: - ArtifactTitle (G5 C8)

// NOTE: RemoteImagePipeline/G5: the artifact page titles itself from the document: the
// `<title>`, then the first `<h1>`, then the kind label. Pure string scan, no parser,
// tested on Linux.

/// The artifact page's title, extracted from the document itself.
public enum ArtifactTitle {
    /// The first non-blank `<title>…</title>`, else the first `<h1>…</h1>` with its inner
    /// tags stripped, else nil (the caller falls back to the kind label or file name).
    /// Matching is case-insensitive and spans lines; entities are left raw.
    public static func extract(html: String) -> String? {
        if let title = tagContent(html, tag: "title"), !title.isEmpty {
            return title
        }
        if let heading = tagContent(html, tag: "h1"), !heading.isEmpty {
            return heading
        }
        return nil
    }

    /// The text between the first `<tag …>` and its `</tag>`, with inner tags stripped
    /// and surrounding whitespace trimmed. Nil when the element is absent or blank.
    private static func tagContent(_ html: String, tag: String) -> String? {
        let lower = html.lowercased()
        guard let openStart = lower.range(of: "<\(tag)") else { return nil }
        guard let openEnd = html[openStart.upperBound...].firstIndex(of: ">") else { return nil }
        let afterOpen = html.index(after: openEnd)
        guard let closeStart = lower[afterOpen...].range(of: "</\(tag)>") else { return nil }
        let inner = String(html[afterOpen..<closeStart.lowerBound])
        let stripped = stripTags(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Removes `<…>` spans. Quotes inside attributes cannot smuggle a `>` past this —
    /// an attribute value containing `>` ends the span early and leaves text behind,
    /// which is the safe direction for a title (more text, never less document).
    private static func stripTags(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inside = false
        for character in text {
            if character == "<" { inside = true; continue }
            if character == ">" { inside = false; continue }
            if !inside { out.append(character) }
        }
        return out
    }
}
