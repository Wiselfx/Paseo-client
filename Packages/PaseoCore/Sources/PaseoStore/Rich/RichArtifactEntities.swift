import Foundation

// V2.3 — some models (and some providers) HTML-escape their own output: a fence or an
// inline SVG arrives as `&lt;div ...&gt;` / `A --&gt; B` instead of markup. The escaping
// is in the text we receive (the daemon log of the test conversation shows it verbatim),
// so the fix belongs at the one boundary that turns text into a page or a diagram. Only
// those bodies are decoded: ordinary prose and ordinary code blocks keep every entity
// exactly as the model wrote it.

/// The five basic HTML entities, decoded for artifact and diagram bodies only.
public enum RichArtifactEntities {
    /// The basic entities, longest-first so a single pass never double-decodes
    /// (`&amp;lt;` becomes `&lt;`, not `<`).
    private static let entities: [(name: String, text: Character)] = [
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&amp;", "&"),
    ]

    /// True when a body is entirely escaped markup: it carries entity forms and no raw
    /// `<` or `>` at all. A body that mixes both is ambiguous — it is left alone, so a
    /// code sample that merely mentions `&lt;` is never rewritten.
    public static func needsDecoding(_ body: String) -> Bool {
        guard !body.contains("<"), !body.contains(">"), body.contains("&") else {
            return false
        }
        return entities.contains { body.contains($0.name) }
    }

    /// The body with the five basic entities decoded in one left-to-right pass. Entities
    /// outside the five (`&nbsp;`, numeric forms, unknown names) are left verbatim.
    public static func decoded(_ body: String) -> String {
        guard body.contains("&") else { return body }
        var output = ""
        output.reserveCapacity(body.count)
        var index = body.startIndex
        while index < body.endIndex {
            if body[index] == "&" {
                var matched = false
                for entity in entities where body[index...].hasPrefix(entity.name) {
                    output.append(entity.text)
                    index = body.index(index, offsetBy: entity.name.count)
                    matched = true
                    break
                }
                if matched { continue }
            }
            output.append(body[index])
            index = body.index(after: index)
        }
        return output
    }

    /// The one step the detector applies to an artifact or diagram body: decode iff the
    /// whole body is escaped markup, else return it unchanged.
    public static func decodedArtifactBody(_ body: String) -> String {
        needsDecoding(body) ? decoded(body) : body
    }
}
